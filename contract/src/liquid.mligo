#include "manager.mligo"


(* Conversion trick from nat to tez  *)
let to_tez (v : nat) : tez =  v * 1tez

(* Conversion trick from tez to nat  *)
let to_nat (x: tez) : nat = x / 1tez

(* Arbitrary token id for the evxta token *)
let evxtz_token_id = 5n

(* 
Amount of treasury tokens to be created in the treasury on creation.
This base amount of tokens will give a more interesting exchange rate when emitted via events *)
let base_treasury_tokens = 1000n

(*  Treasury holds a deposit address and value of 'xtz' that has been deposited in the contract*)
type treasury = {
   addr : address;
   value: nat;
}

(*  The exchange rate is the total amount of evxtz in existence and the total amount of xtz that has been deposited in the contract *)
type exchange_rate = {
  evxtz : nat;
  xtz : nat;
}

(* Event type for emission *)
type event  = Xtz_exchange_rate of exchange_rate

(* 
Top level storage in the contract.
It is comprised of:
- The treasury of XTZ
- Token storage of the evXTZ token
- And the last calculated exchange rate
*)
type liquid_storage = {
  treasury : treasury;
  allocation : token_storage;
  current_rate : exchange_rate;
}

(* Contract entrypoints  *)
type liquid_param =
   Deposit of nat
  | Redeem of nat

(* Event emission *)
let emit_event ( e : event ) : unit= 
    (* This is a fake allocation and casting  to try and make the event visable in Michelson*)
    let (Xtz_exchange_rate rate) = e in
    let _xtz = Michelson.is_nat (int (rate.xtz)) in
    let _evxtz = Michelson.is_nat (int (rate.evxtz)) in
    match _xtz with
    | Some _n -> unit
    | None -> (failwith "This is the emission function" : unit) 


(* Calculate the current exchange rate from the current information in the treasury and the token storage *)
let compute_current_exchange_rate (s : liquid_storage) : exchange_rate = 
    let native = s.treasury.value in
    let token = s.allocation.token_total_supply in
    { evxtz = token; xtz = native; } 

(* type alias for token metadata *)
type token_metadata_info = (string, bytes) map

(* Token metadata for the evXTZ token *)
let evxtz_token_info :  token_metadata_info = Map.literal [
                        ("symbol", 0x455658545a);
                        ("name", 0x4576656e747320005465737420546f6b656e);
                        ("decimals", 0x30);
                      ]

(* Create the evXTZ token*)
let create_evtez_token  (s : liquid_storage) : liquid_storage = 
    let metadata = { token_id = evxtz_token_id;  token_info = evxtz_token_info;} in
    let new_token_storage = create_token (metadata, s.allocation) in
    { s with allocation = new_token_storage}

(* Mint an initial amount of tokens to the treasury *)
let mint_to_treasury (n, s : nat * liquid_storage) : liquid_storage = 
    let _mint_param = Mint_tokens [{ amount = n; owner  = s.treasury.addr; }] in
    let minted_tokens = mint_tokens ([{ amount = n; owner  = s.treasury.addr; }], s.allocation) in
    let new_storage = { s with allocation  = minted_tokens } in
    let new_exchange_rate = compute_current_exchange_rate (new_storage) in
    { new_storage with current_rate = new_exchange_rate }

(* Checks if treasury is empty and creates token to mint initial amount to treasury address*)
let create_token_if_required (s : liquid_storage) : liquid_storage = 
    if s.treasury.value = 0n then
      let after_token_creation = create_evtez_token s in 
      mint_to_treasury (base_treasury_tokens, after_token_creation)
    else 
     s

(* Validates the amount of evXTZ to be redeemed*)
let validate_redemption ( amount_to_redeem, storage : nat * liquid_storage ) : nat = 
    let sender_address : address = Tezos.sender in
    let ledger = storage.allocation.ledger in
    let found : nat option=  Big_map.find_opt (sender_address) ledger in
    match found with
    | Some a ->  let bal  = a in
                 if amount_to_redeem > bal then
                  (failwith "Address doesn't currently enough token to redeem" : nat) 
                 else
                  amount_to_redeem
    | None -> (failwith "Address doesn't currently hold any token to redeem" : nat) 


(* Calculates the amount of evXTZ to be minted from the required XTZ that is being deposited *)
let get_amount_to_mint ( a, r : nat * exchange_rate) : nat = 
    (a / r.xtz) * r.evxtz

(* Calculates the amount of XTZ to be removed from the treasury due to the amount of evXTZ being burned / redeemed *)
let get_amount_to_remove_from_treasury ( a, r : nat * exchange_rate) : nat = 
    (a / r.evxtz) * r.xtz


(* Transfers 'XTZ' to treasury  *)
let transfer_to_treasury (a, s: nat * liquid_storage) : liquid_storage = 
    let treasury_after_transfer =  { s.treasury with value = s.treasury.value + a } in
    { s with treasury = treasury_after_transfer } 


(* Removes 'XTZ' from treasury  *)
let remove_from_treasury (a, s: nat * liquid_storage) : liquid_storage = 
    let treasury_after_transfer =  { s.treasury with value = abs (s.treasury.value - a) } in
    { s with treasury = treasury_after_transfer } 


(*
  ==== DESPOSIT ENTRYPOINT ====
  Deposit XTZ in Treasury.
  Check current exchange rate
  Emit current FX rate as event
  Mint tokens to sender address
*)
let deposit (n, s : nat * liquid_storage) 
    : (operation list) * liquid_storage  =   
    let fx = compute_current_exchange_rate s in
    let _emit = emit_event (Xtz_exchange_rate fx) in
    let after_token_creation = create_token_if_required s in
    let updated_treasury_storage = transfer_to_treasury (n, after_token_creation) in
    let amount_to_mint : nat = get_amount_to_mint (n, fx) in 
    let token_mint : mint_burn_tx = { owner = Tezos.sender; amount = amount_to_mint } in
    let minted_tokens_storage = mint_tokens ([ token_mint  ], updated_treasury_storage.allocation) in
    let final_storage = { updated_treasury_storage with allocation = minted_tokens_storage  } in 
    (([] : operation list), final_storage)
            
(*
  ==== REDEEM ENTRYPOINT ====
  Burn evXTZ token.
  Check current exchange rate
  Emit current FX rate as event
  Remove XTZ from treasury
*)
let redeem (n, s : nat * liquid_storage) 
    : (operation list) * liquid_storage  =   
    let fx = compute_current_exchange_rate s in
    let _emit = emit_event (Xtz_exchange_rate fx) in
    let amount_to_remove : nat = get_amount_to_remove_from_treasury (n, fx) in
    let updated_treasury_storage = remove_from_treasury (amount_to_remove, s) in
    let token_mint : mint_burn_tx = { owner = Tezos.sender; amount = n } in
    let burned_tokens_storage = burn_tokens ([ token_mint  ], s.allocation) in
    let final_storage = { updated_treasury_storage with allocation = burned_tokens_storage  } in 
    (([] : operation list), final_storage)



(* Contract entrypoint *)
let liquid_main
    (param, s : liquid_param * liquid_storage)
    : (operation list) * liquid_storage = 
      match param with
      | Deposit t -> deposit (t, s)
      | Redeem n -> redeem (n, s)

