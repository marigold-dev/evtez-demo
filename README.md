# How to start (Non-nix)

## Indexer and Visualizer

1. Get [Rust Up](https://rustup.rs)
2. `rustup toolchain install nightly`
3. `cargo install wasm-pack`
4. Get your Flextesa Alphabox running, shipped with alpha protocol having event support, serving at port 20000 by default
    - It is recommended to run it with `docker`
    ```
    docker run --rm --name my-sandbox --detach -p 20000:20000 \
       -e block_time=3 \
       oxheadalpha/flextesa kathmandubox start
    ```
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

