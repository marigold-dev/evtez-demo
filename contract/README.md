# liquid-dapp
Simple liquid staking dapp to demonstrate event emission in Tezos

## Building

The easiest way to build is to use `nix`. With nix installed you can spin up a development shell in the project root using: 

```nix
nix develop
```

Once in the shell, use `build` to compile the ligo liquid contract.

## Patching the Michelson code

Ligo doesn't currently support event emission so that compiled Michelson code needs to be adjusted to emit the events correctly.  In the resulting compiled code for the liquid contract `liquid.tz` there is a string marker to help narrow down the place that needs to be amended.  In the code one can look for a string "This is the emission function".  The surrounding code should be of the following format: 

```Michelson
         APPLY ;
         LAMBDA
           (pair nat nat)
           unit
           { CDR ;
             INT ;
             ISNAT ;
             IF_NONE
               { PUSH string "This is the emission function" ; FAILWITH }
               { DROP ; UNIT } } ;
```

The `(pair nat nat)` is the liquid exchange rate that needs to be emited.  This can be accomplished with the following: 

```Michelson
PUSH nat ???; PUSH string "xrate"; EMIT
```

This needs to be patched in between the first `APPLY;` and the callsite of the lambda `LAMBDA` so the patched code should look like the following:

```Michelson
         APPLY ;
         PUSH nat ???; PUSH string "xrate"; EMIT
         LAMBDA
           (pair nat nat)
           unit
           { CDR ;
             INT ;
             ISNAT ;
             IF_NONE
               { PUSH string "This is the emission function" ; FAILWITH }
               { DROP ; UNIT } } ;
```

Once the compiled code has been patched it can then be deployed.

## Deploy