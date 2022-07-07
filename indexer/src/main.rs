#![feature(let_else, result_option_inspect)]
use std::{fmt::Debug, net::SocketAddr, time::Duration};

use anyhow::{bail, Result};
use clap::Parser;
use futures::{pin_mut, prelude::*};
use hyper::{Client, StatusCode, Uri};
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;
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
    data: JsonValue,
    #[serde(rename = "type")]
    ty: JsonValue,
}

#[derive(Deserialize)]
struct TezBlock {
    #[serde(default)]
    operations: Vec<JsonValue>,
}

#[derive(Deserialize)]
struct TezOperation {
    #[serde(default)]
    contents: Vec<TezOperationContent>,
}

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum TezOperationContent {
    Transaction {
        metadata: TezTransactionOperationMetadata,
        destination: String,
    },
    Reveal,
    Origination,
    Delegation,
    RegisterGlobalConstant,
    SetDepositsLimit,
    IncreasePaidStorage,
    TxRollupOrigination,
    TxRollupSubmitBatch,
    TxRollupCommit,
    TxRollupReturnBond,
    TxRollupFinalizeCommitment,
    TxRollupRemoveCommitment,
    TxRollupRejection,
    TxRollupDispatchTickets,
    TransferTicket,
    ScRollupOriginate,
    ScRollupAddMessages,
    ScRollupCement,
    ScRollupPublish,
    ScRollupRefute,
    ScRollupTimeout,
    ScRollupExecuteOutboxMessage,
    ScRollupRecoverBond,
    ScRollupDalSlotSubscribe,
    DalPublishSlotHeader,
    Endorsement,
    Preendorsement,
    DalSlotAvailability,
    SeedNonceRelevation,
    VdfRelevation,
    DoubleEndorsementEvidence,
    DoublePreendorsementEvidence,
    DoubleBakingEvidence,
    ActivateAccount,
    Proposals,
    Ballot,
    FailingNoop,
}

#[derive(Deserialize)]
struct TezTransactionOperationMetadata {
    #[serde(default)]
    internal_operation_results: Vec<TezInternalOperationResult>,
}

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum TezInternalOperationResult {
    /// event
    Event {
        #[serde(rename = "type")]
        ty: JsonValue,
        source: String,
        tag: Option<String>,
        payload: JsonValue,
    },
    /// transaction, but we do not care
    Transaction,
    /// origination, but we do not care
    Origination,
    /// delegation, but we do not care
    Delegation,
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
            let val = TezBlock::deserialize(&val)?;
            let mut events = vec![];
            let Some(operations) = val.operations.get(3) else { return Ok(events) };
            let operations = Vec::<TezOperation>::deserialize(operations)
                .inspect_err(|e| error!(?e, "TezOperation"))?;
            for op in operations {
                for content in op.contents {
                    let TezOperationContent::Transaction { destination, metadata, .. } = content else { continue };
                    for event in metadata.internal_operation_results {
                        let TezInternalOperationResult::Event { ty, source, tag, payload } = event else { continue };
                        events.push(Event {
                            level,
                            payer: source.clone(),
                            emitter: destination.clone(),
                            data: payload,
                            tag: tag.unwrap_or_else(|| "default".into()),
                            ty,
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
