#[global_allocator]
static ALLOC: wee_alloc::WeeAlloc = wee_alloc::WeeAlloc::INIT;

use anyhow::Result;
use plotters::prelude::*;
use plotters_canvas::CanvasBackend;
use serde::Deserialize;
use wasm_bindgen::{prelude::*, JsCast};
use web_sys::{console::log_1, HtmlCanvasElement, MessageEvent, WebSocket};

macro_rules! console_log {
    ($($t:tt)*) => (::web_sys::console::log_1(&::wasm_bindgen::JsValue::from_str(&format_args!($($t)*).to_string())))
}

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = console)]
    fn log(s: &str);
}

struct Candle {
    // block height
    time: u64,
    low: u64,
    high: u64,
    open: u64,
    close: u64,
}

fn draw_all<B>(b: B, ticks: &[Candle]) -> Result<()>
where
    B: DrawingBackend,
    B::ErrorType: 'static,
{
    let canvas = b.into_drawing_area();
    canvas.fill(&WHITE)?;
    if ticks.is_empty() {
        return Ok(());
    }
    let mut low = ticks[0].low;
    let mut high = ticks[0].high;
    for tick in &ticks[1..] {
        if low > tick.low {
            low = tick.low
        }
        if high < tick.high {
            high = tick.high
        }
    }
    let mut chart = ChartBuilder::on(&canvas)
        .x_label_area_size(40)
        .y_label_area_size(40)
        .caption("Price", ("sans-serif", 10.0).into_font())
        .build_cartesian_2d(0..ticks.len(), low..high + 1)?;
    chart.configure_mesh().light_line_style(&WHITE).draw()?;

    chart.draw_series(ticks.iter().enumerate().map(
        |(
            x,
            Candle {
                low,
                high,
                open,
                close,
                ..
            },
        )| {
            CandleStick::new(
                x,
                *open,
                *high,
                *low,
                *close,
                GREEN.filled(),
                RED.filled(),
                5,
            )
        },
    ))?;
    canvas.present()?;
    Ok(())
}

pub struct Tick {
    time: u64,
    price: u64,
}

fn aggregate(data: &mut [Tick], interval: u64) -> Vec<Candle> {
    if data.is_empty() || interval == 0 {
        return vec![];
    }
    data.sort_unstable_by_key(|tick| tick.time);
    let mut candles = vec![];
    let mut data = &*data;
    while !data.is_empty() {
        let time = data[0].time;
        let next = data.partition_point(|tick| tick.time < time + interval);
        assert!(next > 0);
        let open = data[0].price;
        let close = data[next - 1].price;
        let mut low = open;
        let mut high = open;
        for tick in &data[1..next] {
            if low > tick.price {
                low = tick.price
            }
            if high < tick.price {
                high = tick.price
            }
        }
        candles.push(Candle {
            time,
            low,
            high,
            open,
            close,
        });
        data = &data[next..];
    }
    candles
}

#[wasm_bindgen]
pub struct ContractEventListener {
    contract: String,
    socket: WebSocket,
    on_message: Closure<dyn FnMut(MessageEvent)>,
}

#[derive(Debug, Deserialize)]
struct Event {
    level: u64,
    emitter: String,
    payer: String,
    tag: String,
    data: serde_json::Value,
}

impl ContractEventListener {
    pub fn start(
        host: &str,
        contract: &str,
        mut on_event: impl FnMut(Tick) + 'static,
    ) -> Result<ContractEventListener, JsValue> {
        let url = format!("ws://{host}/contract/event/{contract}");
        let socket = WebSocket::new(&url)?;
        console_log!("listening on {url}");
        let contract_ = contract.to_owned();
        let on_message = Closure::wrap(Box::new(move |e: MessageEvent| {
            if let Some(msg) = e.data().as_string() {
                match serde_json::from_str::<Event>(&msg) {
                    Ok(value) => {
                        console_log!("event: {value:?}");
                        let Event {
                            level,
                            emitter,
                            tag,
                            data,
                            ..
                        } = value;
                        if emitter != contract_ {
                            console_log!("but we are not interested in {emitter}");
                            return;
                        }
                        if tag != "xrate" {
                            console_log!("but we are not interested in {tag}");
                            return;
                        }
                        let price = if let Some(price) = data.as_u64() {
                            price
                        } else {
                            console_log!("{data:?} is not a price");
                            return;
                        };
                        console_log!("xrate: emitter: {emitter}");
                        // TODO: this is just some dummy value
                        on_event(Tick { time: level, price });
                    }
                    Err(e) => console_log!("{msg} is not a json: {e:?}"),
                }
            }
        }) as Box<dyn FnMut(MessageEvent)>);
        socket.set_onmessage(Some(on_message.as_ref().unchecked_ref()));
        Ok(Self {
            contract: contract.into(),
            socket,
            on_message,
        })
    }
}

#[wasm_bindgen]
impl ContractEventListener {
    #[wasm_bindgen]
    pub fn contract(&self) -> String {
        self.contract.clone()
    }
}

#[wasm_bindgen]
pub fn observe_price(
    contract: String,
    node: String,
    interval: u64,
    canvas: HtmlCanvasElement,
) -> Result<ContractEventListener, JsValue> {
    log_1(&JsValue::from_str("observe_price"));
    let mut ticks = vec![];
    let on_event = move |tick| {
        let backend = if let Some(b) = CanvasBackend::with_canvas_object(canvas.clone()) {
            b
        } else {
            console_log!("failing to make a canvas backend");
            return;
        };
        ticks.push(tick);
        let ticks = aggregate(&mut ticks, interval);
        if let Err(e) = draw_all(backend, &ticks) {
            console_log!("draw_all: {e:?}")
        }
    };
    ContractEventListener::start(&node, &contract, on_event)
}
