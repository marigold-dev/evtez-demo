#![feature(let_else)]
use std::{fmt::Debug, net::SocketAddr, time::Duration};

use anyhow::{bail, Result};
use clap::Parser;
use futures::{pin_mut, prelude::*};
use hyper::{Client, StatusCode, Uri};
use serde::{Deserialize, Serialize};
use tracing::{error, info};
use warp::{ws::Message, Filter};

#[derive(Parser, Debug, Clone)]
pub struct IndexerOps {
    node: SocketAddr,
    port: u16,
}

async fn get_head_block_level(node: SocketAddr) -> Result<u64> {
    let uri = Uri::builder()
        .scheme("http")
        .authority(node.to_string())
        .path_and_query("/chains/main/blocks/head/header")
        .build()?;
    let client = Client::new();
    let res = client.get(uri).await?;
    match res.status() {
        StatusCode::OK => {
            let body = hyper::body::to_bytes(res).await?;
            let val: serde_json::Value = serde_json::from_slice(&body)?;
            let Some(val) = val.as_object() else { bail!("expected object") };
            let Some(level) = val.get("level") else { bail!("missing key `level` in header") };
            let Some(level) = level.as_u64() else { bail!("expecting integral value for `level`, found {:?}", level) };
            Ok(level)
        }
        status => bail!(
            "node: status code {} while querying for block height",
            status
        ),
    }
}

#[derive(Serialize, Deserialize)]
struct Event {
    level: u64,
    emitter: String,
    payer: String,
    tag: String,
    data: serde_json::Value,
}

async fn poll_block_for_event(node: SocketAddr, level: u64) -> Result<Vec<Event>> {
    let path = format!("/chains/main/blocks/{level}");
    let uri = Uri::builder()
        .scheme("http")
        .authority(node.to_string())
        .path_and_query(path)
        .build()?;
    let client = Client::new();
    let res = client.get(uri).await?;
    match res.status() {
        StatusCode::OK => {
            let body = hyper::body::to_bytes(res).await?;
            let val: serde_json::Value = serde_json::from_slice(&body)?;
            let Some(val) = val.as_object() else { bail!("expected object") };
            let mut events = vec![];
            let Some(operations) = val.get("operations").and_then(|ops| ops.as_array()) else { return Ok(events) };
            let Some(operations) = operations.get(3).and_then(|ops| ops.as_array()) else { return Ok(events) };
            for op in operations {
                let Some(op) = op.as_object() else { continue };
                let Some(contents) = op.get("contents").and_then(|contents| contents.as_array()) else { continue };
                for content in contents {
                    let Some(content) = content.as_object() else { continue };
                    let Some(metadata) = content.get("metadata").and_then(|metadata| metadata.as_object()) else { continue };
                    let Some(operation_result) = metadata.get("operation_result").and_then(|result| result.as_object()) else { continue };
                    let Some(evs) = operation_result.get("events").and_then(|events| events.as_array()) else { continue };
                    let payer = content
                        .get("source")
                        .and_then(|source| source.as_str())
                        .unwrap_or("");
                    let emitter = content
                        .get("destination")
                        .and_then(|source| source.as_str())
                        .unwrap_or("");
                    for event in evs {
                        let Some(event) = event.as_object() else { continue };
                        let tag = event
                            .get("tag")
                            .and_then(|tag| tag.as_str())
                            .unwrap_or("")
                            .to_owned();
                        let Some(data) = event.get("data") else { continue };
                        events.push(Event {
                            level,
                            payer: payer.to_owned(),
                            emitter: emitter.to_owned(),
                            data: data.clone(),
                            tag,
                        });
                    }
                }
            }
            Ok(events)
        }
        status => bail!(
            "node: status code {} while querying for block height",
            status
        ),
    }
}

async fn track<S>(node: SocketAddr, sink: S)
where
    S: Sink<Event>,
    S::Error: Debug,
{
    let mut level = 0;
    pin_mut!(sink);
    'main_loop: loop {
        match get_head_block_level(node).await {
            Ok(max_level) => {
                if max_level >= level {
                    info!("found block {max_level}, expecting {level}");
                    for level_now in level..=max_level {
                        info!("processing block {level_now}");
                        match poll_block_for_event(node, level_now).await {
                            Ok(events) => {
                                for e in events {
                                    if let Err(e) = sink.send(e).await {
                                        error!("track: sink: broken pipe, {:?}", e);
                                        break 'main_loop;
                                    }
                                }
                            }
                            Err(e) => {
                                error!("track: poll block: {:?}", e);
                                tokio::time::sleep(Duration::from_secs(1)).await;
                                break;
                            }
                        }
                        info!("block {level_now} delivered");
                        level = level_now;
                    }
                    level += 1;
                } else {
                    tokio::time::sleep(Duration::from_secs(1)).await;
                }
            }
            Err(e) => {
                error!("track: err: {e:?}");
                break;
            }
        }
    }
}

#[tokio::main]
async fn main() {
    pretty_env_logger::init();
    let ops = IndexerOps::parse();
    let port = ops.port;
    let routes = warp::path!("contract" / "event" / String)
        .and(warp::ws())
        .map(move |contract, ws: warp::ws::Ws| {
            let IndexerOps { node, .. } = ops;
            ws.on_upgrade(move |ws| {
                let (tx, _) = ws.split();
                info!("ws: tracking events from {contract}");
                track(
                    node,
                    tx.sink_map_err(<anyhow::Error>::from)
                        .with(|event| async move {
                            let json = serde_json::to_string(&event)?;
                            Ok::<_, anyhow::Error>(Message::text(json))
                        }),
                )
            })
        });
    warp::serve(routes).run(([0, 0, 0, 0], port)).await
}
