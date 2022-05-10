

#include "token.mligo"

type mint_burn_tx =
[@layout:comb]
{
  owner : address;
  amount : nat;
}

type mint_burn_tx_param =  mint_burn_tx list

(* `token_manager` entry points *)
type token_manager =
  | Create_token of token_metadata
  | Mint_tokens of mint_burn_tx_param
  | Burn_tokens of mint_burn_tx_param

let create_token (metadata, storage
    : token_metadata * token_storage) : token_storage =
  (* extract token id *)
  let new_token_id = metadata.token_id in
  let existing_meta = Big_map.find_opt new_token_id storage.token_metadata in
  match existing_meta with
  | Some _m -> storage
  | None ->
    let meta = Big_map.add new_token_id metadata storage.token_metadata in
    let supply = storage.token_total_supply in
    { storage with
      token_metadata = meta;
      token_total_supply = supply;
    }

let  mint_update_balances (txs, ledger : (mint_burn_tx list) * ledger) : ledger =
  let mint = fun (l, tx : ledger * mint_burn_tx) ->
    inc_balance (tx.owner, tx.amount, l) in
  List.fold mint txs ledger

let mint_update_total_supply (txs, total_supplies
    : (mint_burn_tx list) * token_total_supply) : token_total_supply =
  let update = fun (supplies, tx : token_total_supply * mint_burn_tx) -> supplies + tx.amount in
  List.fold update txs total_supplies

let mint_tokens (param, storage : mint_burn_tx_param * token_storage)
    : token_storage =
    let new_ledger = mint_update_balances (param, storage.ledger) in
    let new_supply = mint_update_total_supply (param, storage.token_total_supply) in
    let new_s = { storage with
      ledger = new_ledger;
      token_total_supply = new_supply;
    } in
    new_s

let burn_update_balances(txs, ledger : (mint_burn_tx list) * ledger) : ledger =
  let burn = fun (l, tx : ledger * mint_burn_tx) ->
    dec_balance (tx.owner, tx.amount, l) in
  List.fold burn txs ledger

let validate_burn_amount (s, n: nat * nat) : nat = 
    let int_supply  = int (s) in
    let int_amount = int (n) in 
    let new_supply = int_supply - int_amount in
    if new_supply < 0  then
      (failwith insufficient_balance : nat)
    else
     abs (new_supply)

let burn_update_total_supply (txs, total_supplies
    : (mint_burn_tx list) * token_total_supply) : token_total_supply =
  let update = fun (supplies, tx : token_total_supply * mint_burn_tx) -> validate_burn_amount (supplies, tx.amount) in
  List.fold update txs total_supplies

let burn_tokens (param, storage : mint_burn_tx_param * token_storage)
    : token_storage =
    let new_ledger = burn_update_balances (param, storage.ledger) in
    let new_supply = burn_update_total_supply (param, storage.token_total_supply) in
    let new_s = { storage with
      ledger = new_ledger;
      token_total_supply = new_supply;
    } in
    new_s


let token_manager (param, s : token_manager * token_storage)
    : (operation list) * token_storage =
  match param with
  | Create_token token_metadata ->
    let new_s = create_token (token_metadata, s) in
    (([]: operation list), new_s)

  | Mint_tokens param ->
    let new_s = mint_tokens (param, s) in
    ([] : operation list), new_s
  | Burn_tokens param ->
   let new_s = burn_tokens (param, s) in
   ([] : operation list), new_s
