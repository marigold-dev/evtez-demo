const visualizer = import('./pkg');
async function init(contract, node) {
    const { ContractEventListener, observe_price } = window.__VISUALIZER = await visualizer;
    if (window.__CHART instanceof ContractEventListener)
        window.__CHART.free();
    const canvas = document.getElementById("chart");
    window.__CHART = observe_price(contract, node, BigInt(5), canvas);
}

document.addEventListener("DOMContentLoaded", _ => {
    document.getElementById("action").addEventListener("click", _ => {
        const contract = document.getElementById("contract").value;
        const node = document.getElementById("node").value;
        init(contract, node).catch(console.error);
    });
});