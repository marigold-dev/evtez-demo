# How to start

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