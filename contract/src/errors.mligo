(** One of the specified `token_id`s is not defined within the FA2 contract *)
let token_undefined = "TOKEN_UNDEFINED" 
(** 
A token owner does not have sufficient balance to transfer tokens from
owner's account 
*)
let insufficient_balance = "INSUFFICIENT_BALANCE"
(** A transfer failed because of `operator_transfer_policy == No_transfer` *)
let tx_denied = "TX_DENIED"
(** 
A transfer failed because `operator_transfer_policy == Owner_transfer` and it is
initiated not by the token owner 
*)
let not_owner = "NOT_OWNER"
(**
A transfer failed because `operator_transfer_policy == Owner_or_operator_transfer`
and it is initiated neither by the token owner nor a permitted operator
 *)
let not_operator = "NOT_OPERATOR"
(** 
`update_operators` entrypoint is invoked and `operator_transfer_policy` is
`No_transfer` or `Owner_transfer`
*)
let operators_not_supported = "OPERATORS_UNSUPPORTED"
(**
Receiver hook is invoked and failed. This error MUST be raised by the hook
implementation
 *)
let receiver_hook_failed = "RECEIVER_HOOK_FAILED"
(**
Sender hook is invoked and failed. This error MUST be raised by the hook
implementation
 *)
let sender_hook_failed = "SENDER_HOOK_FAILED"
(**
Receiver hook is required by the permission behavior, but is not implemented by
a receiver contract
 *)
let receiver_hook_undefined = "RECEIVER_HOOK_UNDEFINED"
(**
Sender hook is required by the permission behavior, but is not implemented by
a sender contract
 *)
let sender_hook_undefined = "SENDER_HOOK_UNDEFINED"

