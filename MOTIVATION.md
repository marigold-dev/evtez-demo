# Event Emission

The motivation behind the event emission demo repository is to provide a simple use-case showing the benefits of the event emission feature in the Tezos protocol.

The demo will consist of three components:
- smart contract
- indexer
- visualizer

## Smart contract

The smart contract, written in CameLIGO, is a simplified version of a liquid staking contract.  A user would deposit XTZ in the contract and would receive a FA2 token (evXTZ) in return.  The value of evXTZ would appreciate due to the contract treasury receiving staking rewards for staking the deposited XTZ to baker.  Actually staking the treasury XTZ to bakers is not required as the focus is on events emitted by the contract rather than a fully working liquid staking protocol.

The event emitted is the exchange rate between the evXTZ and XTZ token.
```ligolang
(*  The exchange rate is the total amount of evxtz in existence and the total amount of xtz that has been deposited in the contract *)
type exchange_rate = {
  evxtz : nat;
  xtz : nat;
}

(* Event type for emission *)
type event  = Xtz_exchange_rate of exchange_rate
```

The event is triggered when any of the contract endpoints are used:

```ligolang
(* Contract entrypoints  *)
type liquid_param =
   Deposit of nat
  | Redeem of nat
```

> As there is no supporting operation for event emission yet in Ligo, the Michelson code output needs to be manually patched to practically emit the event.

Additionally, the amount that is being deposited is adjusted to mimic the underlying baking rewards that would exist in a fully functioning liquid staking protocol.  This is to make the exchange rate being emitted a little more interesting when it comes to the visualization.


## Indexer


## Visualizer

