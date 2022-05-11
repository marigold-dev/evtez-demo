import { ContractEventListener, observe_price } from './pkg';

import React from 'react';
import ReactDOM from 'react-dom/client';
import { Button, Grid, TextField } from '@mui/material';

type GrapherProps = {
    contract?: string,
    node?: string,
};

type GrapherState = {
    listener?: ContractEventListener,
};

class Grapher extends React.Component<GrapherProps, GrapherState> {
    canvas: React.RefObject<HTMLCanvasElement>;

    constructor(prop: GrapherProps) {
        super(prop);
        this.state = {};
        this.canvas = React.createRef();
    }

    render(): React.ReactNode {
        return <Grid container spacing={2}>
            <Grid item xs>
            </Grid>
            <Grid item xs={6}>
                <canvas ref={this.canvas} width={400} height={400} />
            </Grid>
            <Grid item xs>
            </Grid>
        </Grid>;
    }

    componentDidMount(): void {
        const canvas = this.canvas.current;
        const { contract, node } = this.props;
        if (contract)
            this.setState({
                listener: observe_price(contract, node, BigInt(5), canvas),
            });
    }

    componentDidUpdate(
        prevProps: Readonly<GrapherProps>,
        prevState: Readonly<GrapherState>,
        snapshot?: any
    ): void {
        let { contract: prevContract, node: prevNode } = prevProps;
        let { contract, node } = this.props;
        if (prevContract != contract || prevNode != node) {
            if (this.state.listener)
                this.state.listener.free();
            const canvas = this.canvas.current;
            if (contract)
                this.setState({
                    listener: observe_price(contract, node, BigInt(5), canvas),
                });
        }
    }

    componentWillUnmount(): void {
        if (this.state.listener) {
            this.state.listener.free();
        }
    }
}

type AppState = {
    contract?: string;
    node?: string;
    contractInput?: string;
    nodeInput?: string;
};

class App extends React.Component<{}, AppState> {
    constructor(props: {}) {
        super(props);
        this.state = {};
    }

    track() {
        this.setState({
            contract: this.state.contractInput,
            node: this.state.nodeInput,
        })
    }

    render() {
        return <Grid container spacing={2}>
            <Grid item xs={12}>
                <Grapher contract={this.state.contract} node={this.state.node} />
            </Grid>
            <Grid item xs={1}></Grid>
            <Grid item xs={3}>
                <TextField
                    variant='filled'
                    label='Contract Address'
                    value={this.state.contractInput}
                    onChange={e => this.setState({ contractInput: e.target.value })} />
            </Grid>
            <Grid item xs={3}>
                <TextField
                    variant='filled'
                    label='Indexer Address'
                    value={this.state.nodeInput}
                    onChange={e => this.setState({ nodeInput: e.target.value })} />
            </Grid>
            <Grid item xs={1}><Button variant='contained' onClick={() => this.track()}>Track</Button></Grid>
        </Grid>;
    }
}

let root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);