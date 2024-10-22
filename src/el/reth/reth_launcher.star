shared_utils = import_module("../../shared_utils/shared_utils.star")
input_parser = import_module("../../package_io/input_parser.star")
el_context = import_module("../el_context.star")
el_admin_node_info = import_module("../el_admin_node_info.star")
el_shared = import_module("../el_shared.star")
node_metrics = import_module("../../node_metrics_info.star")
constants = import_module("../../package_io/constants.star")
mev_rs_builder = import_module("../../mev/mev-rs/mev_builder/mev_builder_launcher.star")

RPC_PORT_NUM = 8545
L2_START_RPC_PORT_NUM = 10110
L2_RPC_PORT_OFFSET = 10000
WS_PORT_NUM = 8546
DISCOVERY_PORT_NUM = 30303
ENGINE_RPC_PORT_NUM = 8551
METRICS_PORT_NUM = 9001

# The min/max CPU/memory that the execution node can use
EXECUTION_MIN_CPU = 100
EXECUTION_MIN_MEMORY = 256

# Paths
METRICS_PATH = "/metrics"

# The dirpath of the execution data directory on the client container
EXECUTION_DATA_DIRPATH_ON_CLIENT_CONTAINER = "/data/reth/execution-data"

ENTRYPOINT_ARGS = ["sh", "-c"]

VERBOSITY_LEVELS = {
    constants.GLOBAL_LOG_LEVEL.error: "v",
    constants.GLOBAL_LOG_LEVEL.warn: "vv",
    constants.GLOBAL_LOG_LEVEL.info: "vvv",
    constants.GLOBAL_LOG_LEVEL.debug: "vvvv",
    constants.GLOBAL_LOG_LEVEL.trace: "vvvvv",
}


def launch(
    plan,
    launcher,
    service_name,
    image,
    participant_log_level,
    global_log_level,
    # If empty then the node will be launched as a bootnode
    existing_el_clients,
    el_min_cpu,
    el_max_cpu,
    el_min_mem,
    el_max_mem,
    extra_params,
    extra_env_vars,
    extra_labels,
    persistent,
    el_volume_size,
    tolerations,
    node_selectors,
    port_publisher,
    participant_index,
):
    log_level = input_parser.get_client_log_level_or_default(
        participant_log_level, global_log_level, VERBOSITY_LEVELS
    )

    network_name = shared_utils.get_network_name(launcher.network)

    el_min_cpu = int(el_min_cpu) if int(el_min_cpu) > 0 else EXECUTION_MIN_CPU
    el_max_cpu = (
        int(el_max_cpu)
        if int(el_max_cpu) > 0
        else constants.RAM_CPU_OVERRIDES[network_name]["reth_max_cpu"]
    )
    el_min_mem = int(el_min_mem) if int(el_min_mem) > 0 else EXECUTION_MIN_MEMORY
    el_max_mem = (
        int(el_max_mem)
        if int(el_max_mem) > 0
        else constants.RAM_CPU_OVERRIDES[network_name]["reth_max_mem"]
    )

    el_volume_size = (
        el_volume_size
        if int(el_volume_size) > 0
        else constants.VOLUME_SIZE[network_name]["reth_volume_size"]
    )

    cl_client_name = service_name.split("-")[3]

    config = get_config(
        plan,
        launcher.el_cl_genesis_data,
        launcher.jwt_file,
        launcher.network,
        image,
        service_name,
        existing_el_clients,
        cl_client_name,
        log_level,
        el_min_cpu,
        el_max_cpu,
        el_min_mem,
        el_max_mem,
        extra_params,
        extra_env_vars,
        extra_labels,
        persistent,
        el_volume_size,
        tolerations,
        node_selectors,
        launcher.builder,
        port_publisher,
        participant_index,
    )

    service = plan.add_service(service_name, config)

    enode = el_admin_node_info.get_enode_for_node(
        plan, service_name, constants.RPC_PORT_ID
    )

    metric_url = "{0}:{1}".format(service.ip_address, METRICS_PORT_NUM)
    reth_metrics_info = node_metrics.new_node_metrics_info(
        service_name, METRICS_PATH, metric_url
    )

    http_url = "http://{0}:{1}".format(service.ip_address, RPC_PORT_NUM)
    ws_url = "ws://{0}:{1}".format(service.ip_address, WS_PORT_NUM)

    return el_context.new_el_context(
        "reth",
        "",  # reth has no enr
        enode,
        service.ip_address,
        RPC_PORT_NUM,
        WS_PORT_NUM,
        ENGINE_RPC_PORT_NUM,
        http_url,
        ws_url,
        service_name,
        [reth_metrics_info],
    )

def parse_extra_params(extra_params):
    cmd = []
    num_of_l2s = None
    skip_next = False
    for i in range(0, len(extra_params)):
        if skip_next:
            skip_next = False
            continue

        param = extra_params[i]
        if param == "--num_of_l2s":
            if i + 1 < len(extra_params):
                num_of_l2s = int(extra_params[i + 1])
                skip_next = True  # Skip the next iteration
            else:
                fail("--num_of_l2s flag provided without a value")
        else:
            cmd.append(param)
    return cmd, num_of_l2s

def get_config(
    plan,
    el_cl_genesis_data,
    jwt_file,
    network,
    image,
    service_name,
    existing_el_clients,
    cl_client_name,
    verbosity_level,
    el_min_cpu,
    el_max_cpu,
    el_min_mem,
    el_max_mem,
    extra_params,
    extra_env_vars,
    extra_labels,
    persistent,
    el_volume_size,
    tolerations,
    node_selectors,
    builder,
    port_publisher,
    participant_index,
):
    public_ports = {}
    discovery_port = DISCOVERY_PORT_NUM
    
    # By default it is 1 anyways, only need to supply this param in config file if bigger than 0
    num_of_l2s = 0
    cmd_from_extra_params = []
    if len(extra_params) > 0:
        cmd_from_extra_params, num_of_l2s = parse_extra_params(extra_params)

    if port_publisher.el_enabled:
        public_ports_for_component = shared_utils.get_public_ports_for_component(
            "el", port_publisher, participant_index
        )
        public_ports, discovery_port = el_shared.get_general_el_public_port_specs(
            public_ports_for_component
        )
        additional_public_port_assignments = {
            constants.RPC_PORT_ID: public_ports_for_component[2],
            constants.WS_PORT_ID: public_ports_for_component[3],
            constants.METRICS_PORT_ID: public_ports_for_component[4],
            constants.L2_RPC_PORT_ID_1: public_ports_for_component[5],
        }

        # Currently supporting 10 but 1 (10110) is "default" exposed
        if num_of_l2s > 1:
            for i in range(1, num_of_l2s):
                if i == 1:
                    additional_public_port_assignments[constants.L2_RPC_PORT_ID_2] = public_ports_for_component[6]
                elif i == 2:
                    additional_public_port_assignments[constants.L2_RPC_PORT_ID_3] = public_ports_for_component[7]
                elif i == 3:
                    additional_public_port_assignments[constants.L2_RPC_PORT_ID_4] = public_ports_for_component[8]
                elif i == 4:
                    additional_public_port_assignments[constants.L2_RPC_PORT_ID_5] = public_ports_for_component[9]
                elif i == 5:
                    additional_public_port_assignments[constants.L2_RPC_PORT_ID_6] = public_ports_for_component[10]
                elif i == 6:
                    additional_public_port_assignments[constants.L2_RPC_PORT_ID_7] = public_ports_for_component[11]
                elif i == 7:
                    additional_public_port_assignments[constants.L2_RPC_PORT_ID_8] = public_ports_for_component[12]
                elif i == 8:
                    additional_public_port_assignments[constants.L2_RPC_PORT_ID_9] = public_ports_for_component[13]
                elif i == 9:
                    additional_public_port_assignments[constants.L2_RPC_PORT_ID_10] = public_ports_for_component[14]

        public_ports.update(
            shared_utils.get_port_specs(additional_public_port_assignments)
        )

    used_port_assignments = {
        constants.TCP_DISCOVERY_PORT_ID: discovery_port,
        constants.UDP_DISCOVERY_PORT_ID: discovery_port,
        constants.ENGINE_RPC_PORT_ID: ENGINE_RPC_PORT_NUM,
        constants.RPC_PORT_ID: RPC_PORT_NUM,
        constants.L2_RPC_PORT_ID_1: L2_START_RPC_PORT_NUM,
        constants.WS_PORT_ID: WS_PORT_NUM,
        constants.METRICS_PORT_ID: METRICS_PORT_NUM,
    }

    if num_of_l2s > 1:
            for i in range(1, num_of_l2s):
                l2_port_inside_container = L2_START_RPC_PORT_NUM + (i*L2_RPC_PORT_OFFSET)
                if i == 1:
                    used_port_assignments[constants.L2_RPC_PORT_ID_2] = l2_port_inside_container
                elif i == 2:
                    used_port_assignments[constants.L2_RPC_PORT_ID_3] = l2_port_inside_container
                elif i == 3:
                    used_port_assignments[constants.L2_RPC_PORT_ID_4] = l2_port_inside_container
                elif i == 4:
                    used_port_assignments[constants.L2_RPC_PORT_ID_5] = l2_port_inside_container
                elif i == 5:
                    used_port_assignments[constants.L2_RPC_PORT_ID_6] = l2_port_inside_container
                elif i == 6:
                    used_port_assignments[constants.L2_RPC_PORT_ID_7] = l2_port_inside_container
                elif i == 7:
                    used_port_assignments[constants.L2_RPC_PORT_ID_8] = l2_port_inside_container
                elif i == 8:
                    used_port_assignments[constants.L2_RPC_PORT_ID_9] = l2_port_inside_container
                elif i == 9:
                    used_port_assignments[constants.L2_RPC_PORT_ID_10] = l2_port_inside_container

    used_ports = shared_utils.get_port_specs(used_port_assignments)

    cmd = [
        "/usr/local/bin/mev build" if builder else "reth",
        "node",
        "-{0}".format(verbosity_level),
        "--datadir=" + EXECUTION_DATA_DIRPATH_ON_CLIENT_CONTAINER,
        "--chain={0}".format(
            network
            if network in constants.PUBLIC_NETWORKS
            else constants.GENESIS_CONFIG_MOUNT_PATH_ON_CONTAINER + "/genesis.json"
        ),
        "--http",
        "--http.port={0}".format(RPC_PORT_NUM),
        "--http.addr=0.0.0.0",
        "--http.corsdomain=*",
        # WARNING: The admin info endpoint is enabled so that we can easily get ENR/enode, which means
        #  that users should NOT store private information in these Kurtosis nodes!
        "--http.api=admin,net,eth,web3,debug,trace",
        "--ws",
        "--ws.addr=0.0.0.0",
        "--ws.port={0}".format(WS_PORT_NUM),
        "--ws.api=net,eth",
        "--ws.origins=*",
        "--nat=extip:" + port_publisher.nat_exit_ip,
        "--authrpc.port={0}".format(ENGINE_RPC_PORT_NUM),
        "--authrpc.jwtsecret=" + constants.JWT_MOUNT_PATH_ON_CONTAINER,
        "--authrpc.addr=0.0.0.0",
        "--metrics=0.0.0.0:{0}".format(METRICS_PORT_NUM),
        "--discovery.port={0}".format(discovery_port),
        "--port={0}".format(discovery_port),
    ]

    if network == constants.NETWORK_NAME.kurtosis:
        if len(existing_el_clients) > 0:
            cmd.append(
                "--bootnodes="
                + ",".join(
                    [
                        ctx.enode
                        for ctx in existing_el_clients[: constants.MAX_ENODE_ENTRIES]
                    ]
                )
            )
    elif (
        network not in constants.PUBLIC_NETWORKS
        and constants.NETWORK_NAME.shadowfork not in network
    ):
        cmd.append(
            "--bootnodes="
            + shared_utils.get_devnet_enodes(
                plan, el_cl_genesis_data.files_artifact_uuid
            )
        )

    if len(cmd_from_extra_params) > 0:
        cmd.extend([param for param in cmd_from_extra_params])

    cmd_str = " ".join(cmd)

    files = {
        constants.GENESIS_DATA_MOUNTPOINT_ON_CLIENTS: el_cl_genesis_data.files_artifact_uuid,
        constants.JWT_MOUNTPOINT_ON_CLIENTS: jwt_file,
    }

    if persistent:
        files[EXECUTION_DATA_DIRPATH_ON_CLIENT_CONTAINER] = Directory(
            persistent_key="data-{0}".format(service_name),
            size=el_volume_size,
        )

    if builder:
        files[
            mev_rs_builder.MEV_BUILDER_MOUNT_DIRPATH_ON_SERVICE
        ] = mev_rs_builder.MEV_BUILDER_FILES_ARTIFACT_NAME

    return ServiceConfig(
        image=image,
        ports=used_ports,
        public_ports=public_ports,
        cmd=[cmd_str],
        files=files,
        entrypoint=ENTRYPOINT_ARGS,
        private_ip_address_placeholder=constants.PRIVATE_IP_ADDRESS_PLACEHOLDER,
        min_cpu=el_min_cpu,
        max_cpu=el_max_cpu,
        min_memory=el_min_mem,
        max_memory=el_max_mem,
        env_vars=extra_env_vars,
        labels=shared_utils.label_maker(
            constants.EL_TYPE.reth,
            constants.CLIENT_TYPES.el,
            image,
            cl_client_name,
            extra_labels,
        ),
        tolerations=tolerations,
        node_selectors=node_selectors,
    )


def new_reth_launcher(el_cl_genesis_data, jwt_file, network, builder=False):
    return struct(
        el_cl_genesis_data=el_cl_genesis_data,
        jwt_file=jwt_file,
        network=network,
        builder=builder,
    )
