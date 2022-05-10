(**
Reference implementation of the FA2 operator storage, config API and
helper functions
*)

#include "errors.mligo"
#include "permissions.mligo"
#include "interface.mligo"


(**
(owner, operator) -> unit
To be part of FA2 storage to manage permitted operators
*)
type owner = address
type operator = address
type operator_storage = ((owner * operator), unit) big_map

(**
  Updates operator storage using an `update_operator` command.
  Helper function to implement `Update_operators` FA2 entrypoint
*)
let update_operators (update, storage : update_operator * operator_storage)
    : operator_storage =
  match update with
  | Add_operator op ->
    Big_map.update (op.owner, op.operator) (Some unit) storage
  | Remove_operator op ->
    Big_map.remove (op.owner, op.operator) storage

(**
Validate if operator update is performed by the token owner.
@param updater an address that initiated the operation; usually `Tezos.sender`.
*)
let validate_update_operators_by_owner (update, updater : update_operator * address)
    : unit =
  let op = match update with
  | Add_operator op -> op
  | Remove_operator op -> op
  in
  if op.owner = updater then unit else failwith not_owner

(**
  Generic implementation of the FA2 `%update_operators` entrypoint.
  Assumes that only the token owner can change its operators.
 *)
let fa2_update_operators (updates, storage
    : (update_operator list) * operator_storage) : operator_storage =
  let updater = Tezos.sender in
  let process_update = (fun (ops, update : operator_storage * update_operator) ->
    let _u = validate_update_operators_by_owner (update, updater) in
    update_operators (update, ops)
  ) in
  List.fold process_update updates storage

(**
  owner * operator * token_id * ops_storage -> unit
*)
type operator_validator = (address * address * operator_storage)-> unit

(**
Create an operator validator function based on provided operator policy.
@param tx_policy operator_transfer_policy defining the constrains on who can transfer.
@return (owner, operator, token_id, ops_storage) -> unit
 *)
let make_operator_validator (tx_policy : operator_transfer_policy) : operator_validator =
  let can_owner_tx, can_operator_tx = match tx_policy with
  | No_transfer -> (failwith tx_denied : bool * bool)
  | Owner_transfer -> true, false
  | Owner_or_operator_transfer -> true, true
  in
  (fun (owner, operator, ops_storage
      : address * address  * operator_storage) ->
    if can_owner_tx && owner = operator
    then unit (* transfer by the owner *)
    else if not can_operator_tx
    then failwith not_owner (* an operator transfer not permitted by the policy *)
    else if Big_map.mem  (owner, operator) ops_storage
    then unit (* the operator is permitted for the token_id *)
    else failwith not_operator (* the operator is not permitted for the token_id *)
  )

(**
Default implementation of the operator validation function.
The default implicit `operator_transfer_policy` value is `Owner_or_operator_transfer`
 *)
let default_operator_validator : operator_validator =
  (fun (owner, operator, ops_storage
      : address * address *  operator_storage) ->
    if owner = operator
    then unit (* transfer by the owner *)
    else if Big_map.mem (owner, operator) ops_storage
    then unit (* the operator is permitted for the token_id *)
    else failwith not_operator (* the operator is not permitted for the token_id *)
  )

(**
Validate operators for all transfers in the batch at once
@param tx_policy operator_transfer_policy defining the constrains on who can transfer.
*)
let validate_operator (tx_policy, txs, ops_storage
    : operator_transfer_policy * (transfer list) * operator_storage) : unit =
  let validator = make_operator_validator tx_policy in
  List.iter (fun (tx : transfer) ->
    List.iter (fun (_dst: transfer_destination) ->
      validator (tx.from_, Tezos.sender ,ops_storage)
    ) tx.txs
  ) txs
