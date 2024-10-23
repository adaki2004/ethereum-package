static_files = import_module("../../../static_files/static_files.star")
shared_utils = import_module("../../shared_utils/shared_utils.star")

# let datadir_base = "/data/reth/gwyneth";
# let ipc_base: &str = "/tmp/reth.ipc";

L1_DATA_PATH = "/data/reth/execution-data/"
L2_DATA_BASE = "/data/reth/gwyneth/"
IPC_BASE = "/tmp/reth.ipc"
RBUILDER_CONFIG_FILE = "config-gwyneth-reth.toml"

L2_DATA_PERSISTENCE_KEY = "l2-data"
L2_IPC_PERSISTENCE_KEY = "reth-ipc"
RBUILDER_RPC_PORT = "9646"


USED_PORTS = {
    "http": shared_utils.new_port_spec(
        RBUILDER_RPC_PORT, shared_utils.TCP_PROTOCOL
    )
}

def launch(
    plan,
    beacon_uri,
    el_l2_networks,
    el_context,
    mev_params,
    global_node_selectors,
):
    el_rpc_uri = "http://{0}:{1}".format(el_context.ip_addr, el_context.rpc_port_num)
    l2_data_paths = []
    l2_ipc_paths = []
    files = {
        L1_DATA_PATH: Directory(persistent_key="data-{0}".format(el_context.service_name))
    }
    for i, network in enumerate(el_l2_networks).
        l2_data_path.append("{0}-{1}".format(L2_DATA_BASE, network))
        l2_ipc_paths.append("{0}-{1}".format(IPC_BASE, network))
        files[l2_data_path[i]] = Directory(persistent_key="{0}-{1}".format(L2_DATA_PERSISTENCE_KEY, network),)
        files[l2_ipc_paths[i]] = "{0}-{1}.ipc".format(L2_IPC_PERSISTENCE_KEY, network)


    config_template_file = read_file(static_files.GWYNETH_CONFIG_TEMPLATE_FILEPATH)
    template_data = new_rbuilder_template_data(
        beacon_uri,
        el_rpc_uri,
        l2_data_paths,
        l2_ipc_paths,
        mev_params
    )
    template_and_data = shared_utils.new_template_and_data(config_template_file, template_data)
    config_artifact = plan.render_templates({ RBUILDER_CONFIG_FILE: template_and_data }, RBUILDER_CONFIG_FILE)

    plan.print("Rbuilder config {0}".format(template_data))

    service_config = ServiceConfig(
        image=mev_params.mev_rbuilder_image,
        ports=USED_PORTS,
        files=files,
        entrypoint=["/app/rbuilder"],
        cmd=[
            "run",
            RBUILDER_CONFIG_FILE
        ],
    )
    service_name = "{0}-rbuilder".format(el_context.service_name)
    
    plan.add_service(service_name, service_config)


def new_rbuilder_template_data(
    beacon_uri,
    el_rpc_uri,
    l2_data_paths,
    l2_ipc_paths,
    mev_params
):
    return {
        "BeaconUri": beacon_uri,
        "RbuilderRpcPort": RBUILDER_RPC_PORT,
        "RethRpcUri": el_rpc_uri,
        "L1DataPath": L1_DATA_PATH,
        "L2DataPaths": l2_data_paths,
        "L2IpcPaths": l2_ipc_paths,
        "L1ProposerPk": mev_params.l1_proposer_pk,
        "L1GwynethAddress": mev_params.l1_gwyneth_address,
    }