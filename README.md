# How to start (Non-nix)

## Indexer and Visualizer

1. Get [Rust Up](https://rustup.rs)
2. `rustup toolchain install nightly`
3. `cargo install wasm-pack`
4. Get your Flextesa Alphabox running, shipped with alpha protocol having event support, serving at port 20000 by default
4. Start with indexer
    - `(cd indexer; cargo run -- 127.0.0.1:2000 <indexer-port-of-your-choosing>)`
5. Start the visualizer
    - `(cd visualizer; npm run serve)`
6. Deploy the contract and note down the contract address
7. Go to the visualizer page and key in the contract address and the indexer address like `localhost:<indexer-port-of-your-choosing>`.
8. Interact with the contract to see effects. Open up the browser `dev-tools` window for logs.

## Ligo Contract

1. Ensure that you have ligo installed on your machine - https://www.ligolang.org/docs/intro/installation/
2. The `do` script file contains three ligo related operations:
- build
- dry-run
- deploy

Usage of the do script is:

```txt
==============================================================
./do <op>
=> where:
=> op = build.              Build compiles the ligo contract and storage
=> op = dryrun.             Performs a dry-run against the liquid contract that deposits a test amount of XTZ
=> op = deploy <address>.   Deploys the smart contract for the passed user address
```

# How to start (Nix)

1. Ensure that you have Nix installed - https://nixos.org/download.html

> The current preferred way is
>  ```bash
>   sh <(curl -L https://nixos.org/nix/install) --daemon
>  ```

2. Enable flakes in the Nix package manager - https://nixos.wiki/wiki/Flakes

> Edit either ~/.config/nix/nix.conf or /etc/nix/nix.conf and add:
> ```
> experimental-features = nix-command flakes
> ```

## Dev Shell

1. To get a dev shell, run the following from the root of the project

```bash
nix develop
```

## Building

There are three components to the repository:
- contract
- indexer
- visualizer

Each component can be built with:
```bash
nix build .#<name>
```
where <name> is the name of the component.

For instance, to build the Ligo contract and associated initial storage:

```bash
nix build .#contract
```
All build outputs will be found under `result/`


# Patching the Michelson code

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
               { DROP; PUSH string "This is the emission function" ; FAILWITH }
               { DROP ; UNIT } } ;
```

The `(pair nat nat)` is the liquid exchange rate that needs to be emited.  This can be accomplished with the following:

```Michelson
EMIT %xrate
```
Replace `DROP; PUSH string "This is the emission function" ; FAILWITH` with the code above.

Once the compiled code has been patched it can then be deployed.

