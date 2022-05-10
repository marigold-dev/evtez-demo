
#include "interface.mligo"
#include "errors.mligo"
#include "operator.mligo"

(* owner -> balance *)
type ledger = (address , nat) big_map

(*  total_supply *)
type token_total_supply = nat

type token_storage = {
  ledger : ledger;
  operators : operator_storage;
  token_total_supply : token_total_supply;
  token_metadata : token_metadata_storage;
}

let get_balance_amt (key, ledger : address * ledger) : nat =
  let bal_opt = Big_map.find_opt key ledger in
  match bal_opt with
  | None -> 0n
  | Some b -> b

let inc_balance (owner, amt, ledger
    : address *  nat * ledger) : ledger =
  let bal = get_balance_amt (owner, ledger) in
  let updated_bal = bal + amt in
  if updated_bal = 0n
  then Big_map.remove owner ledger
  else Big_map.update owner (Some updated_bal) ledger

let dec_balance (owner, amt, ledger
    : address * nat * ledger) : ledger =
  let bal = get_balance_amt (owner, ledger) in
  match Michelson.is_nat (bal - amt) with
  | None -> (failwith insufficient_balance : ledger)
  | Some new_bal ->
    if new_bal = 0n
    then Big_map.remove owner ledger
    else Big_map.update owner (Some new_bal) ledger

(**
Update ledger balances according to the specified transfers. Fails if any of the
permissions or constraints are violated.
@param txs transfers to be applied to the ledger
@param validate_op function that validates of the tokens from the particular owner can be transferred.
 *)
let transfer (txs, validate_op, storage
    : (transfer list) * operator_validator * token_storage)
    : ledger =
  let make_transfer = fun (l, tx : ledger * transfer) ->
    List.fold
      (fun (ll, dst : ledger * transfer_destination) ->
        if not Big_map.mem dst.token_id storage.token_metadata
        then (failwith token_undefined : ledger)
        else
          let _u = validate_op (tx.from_, Tezos.sender,  storage.operators) in
          let lll = dec_balance (tx.from_, dst.amount, ll) in
          inc_balance(dst.to_,  dst.amount, lll)
      ) tx.txs l
  in
  List.fold make_transfer txs storage.ledger

let get_balance (p, ledger, tokens
    : balance_of_param * ledger * token_metadata_storage) : operation =
  let to_balance = fun (r : balance_of_request) ->
    if not Big_map.mem r.token_id tokens
    then (failwith token_undefined : balance_of_response)
    else
      let bal = get_balance_amt (r.owner, ledger) in
      let response : balance_of_response = { request = r; balance = bal; } in
      response
  in
  let responses = List.map to_balance p.requests in
  Tezos.transaction responses 0mutez p.callback


let fa2_main (param, storage : fa2_entry_points * token_storage)
    : (operation  list) * token_storage =
  match param with
  | Transfer txs ->
    (*
    will validate that a sender is either `from_` parameter of each transfer
    or a permitted operator for the owner `from_` address.
    *)
    let new_ledger = transfer (txs, default_operator_validator, storage) in
    let new_storage = { storage with ledger = new_ledger; }
    in ([] : operation list), new_storage

  | Balance_of p ->
    let op = get_balance (p, storage.ledger, storage.token_metadata) in
    [op], storage

  | Update_operators updates ->
    let new_ops = fa2_update_operators (updates, storage.operators) in
    let new_storage = { storage with operators = new_ops; } in
    ([] : operation list), new_storage
