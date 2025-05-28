shared_utils = import_module("../../shared_utils/shared_utils.star")
input_parser = import_module("../../package_io/input_parser.star")
el_context = import_module("../el_context.star")
el_admin_node_info = import_module("../el_admin_node_info.star")
el_shared = import_module("../el_shared.star")
node_metrics = import_module("../../node_metrics_info.star")
constants = import_module("../../package_io/constants.star")
mev_rs_builder = import_module("../../mev/mev-rs/mev_builder/mev_builder_launcher.star")
lighthouse = import_module("../../cl/lighthouse/lighthouse_launcher.star")
flashbots_rbuilder = import_module(
    "../../mev/flashbots/mev_builder/mev_builder_launcher.star"
)

RPC_PORT_NUM = 8545
L2_START_RPC_PORT_NUM = 10110
RPC_ROUTER_PORT_NUM = 32009
# Note: In case we are running more than 7 L2s within kurtosis (for whatever reason)
# there will be a conflict between L2 ports and RPC router port, but since we are just
# using it for devnet, for backward compatibility with Brecht's script, fine as is.
RPC_ROUTER_PUBLIC_PORT = 32009
L2_RPC_PORT_OFFSET = 100
WS_PORT_NUM = 8546
DISCOVERY_PORT_NUM = 30303
ENGINE_RPC_PORT_NUM = 8551
METRICS_PORT_NUM = 9001
RBUILDER_PORT_NUM = 8645
# Paths
METRICS_PATH = "/metrics"

# The dirpath of the execution data directory on the client container
EXECUTION_DATA_DIRPATH_ON_CLIENT_CONTAINER = "/data/reth/execution-data"


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
    participant,
    global_log_level,
    existing_el_clients,
    persistent,
    tolerations,
    node_selectors,
    port_publisher,
    participant_index,
):
    log_level = input_parser.get_client_log_level_or_default(
        participant.el_log_level, global_log_level, VERBOSITY_LEVELS
    )

    cl_client_name = service_name.split("-")[3]

    config = get_config(
        plan,
        launcher,
        participant,
        service_name,
        existing_el_clients,
        cl_client_name,
        log_level,
        persistent,
        tolerations,
        node_selectors,
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
        client_name="reth",
        enode=enode,
        ip_addr=service.ip_address,
        rpc_port_num=RPC_PORT_NUM,
        ws_port_num=WS_PORT_NUM,
        engine_rpc_port_num=ENGINE_RPC_PORT_NUM,
        rpc_http_url=http_url,
        ws_url=ws_url,
        service_name=service_name,
        el_metrics_info=[reth_metrics_info],
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
    launcher,
    participant,
    service_name,
    existing_el_clients,
    cl_client_name,
    log_level,
    persistent,
    tolerations,
    node_selectors,
    port_publisher,
    participant_index,
):
    public_ports = {}
    discovery_port = DISCOVERY_PORT_NUM
    
    # By default it is 1 anyways, only need to supply this param in config file if bigger than 0
    num_of_l2s = 0
    cmd_from_extra_params = []
    if len(participant.el_extra_params) > 0:
        cmd_from_extra_params, num_of_l2s = parse_extra_params(participant.el_extra_params)

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
            constants.RPC_ROUTER_PORT_ID: RPC_ROUTER_PUBLIC_PORT,
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
        constants.RPC_ROUTER_PORT_ID: RPC_ROUTER_PORT_NUM,
        constants.WS_PORT_ID: WS_PORT_NUM,
        constants.METRICS_PORT_ID: METRICS_PORT_NUM,
    }

    if (
        launcher.builder_type == constants.FLASHBOTS_MEV_TYPE
        or launcher.builder_type == constants.COMMIT_BOOST_MEV_TYPE
    ):
        used_port_assignments[constants.RBUILDER_PORT_ID] = RBUILDER_PORT_NUM


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

    cmd = []

    if launcher.builder_type == "mev-rs":
        cmd.append("build")

    cmd.extend(
        [
            "node",
            "-{0}".format(log_level),
            "--datadir=" + EXECUTION_DATA_DIRPATH_ON_CLIENT_CONTAINER,
            "--chain={0}".format(
                launcher.network
                if launcher.network in constants.PUBLIC_NETWORKS
                else constants.GENESIS_CONFIG_MOUNT_PATH_ON_CONTAINER + "/genesis.json"
            ),
            "--http",
            "--http.port={0}".format(RPC_PORT_NUM),
            "--http.addr=0.0.0.0",
            "--http.corsdomain=*",
            "--http.api=admin,net,eth,web3,debug,txpool,trace{0}".format(
                ",flashbots"
                if launcher.builder_type == constants.FLASHBOTS_MEV_TYPE
                or launcher.builder_type == constants.COMMIT_BOOST_MEV_TYPE
                else ""
            ),
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
    )

    if launcher.network == constants.NETWORK_NAME.kurtosis:
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
        launcher.network not in constants.PUBLIC_NETWORKS
        and constants.NETWORK_NAME.shadowfork not in launcher.network
    ):
        cmd.append(
            "--bootnodes="
            + shared_utils.get_devnet_enodes(
                plan, launcher.el_cl_genesis_data.files_artifact_uuid
            )
        )

    if len(cmd_from_extra_params) > 0:
        cmd.extend([param for param in cmd_from_extra_params])

    cmd_str = " ".join(cmd)

    files = {
        constants.GENESIS_DATA_MOUNTPOINT_ON_CLIENTS: launcher.el_cl_genesis_data.files_artifact_uuid,
        constants.JWT_MOUNTPOINT_ON_CLIENTS: launcher.jwt_file,
    }

    if persistent:
        files[EXECUTION_DATA_DIRPATH_ON_CLIENT_CONTAINER] = Directory(
            persistent_key="data-{0}".format(service_name),
            size=int(participant.el_volume_size)
            if int(participant.el_volume_size) > 0
            else constants.VOLUME_SIZE[launcher.network][
                constants.EL_TYPE.reth + "_volume_size"
            ],
        )
    env_vars = {}
    image = participant.el_image
    if launcher.builder_type == constants.MEV_RS_MEV_TYPE:
        files[
            mev_rs_builder.MEV_BUILDER_MOUNT_DIRPATH_ON_SERVICE
        ] = mev_rs_builder.MEV_BUILDER_FILES_ARTIFACT_NAME
    elif (
        launcher.builder_type == constants.FLASHBOTS_MEV_TYPE
        or launcher.builder_type == constants.COMMIT_BOOST_MEV_TYPE
    ):
        image = launcher.mev_params.mev_builder_image
        cl_client_name = service_name.split("-")[4]
        cmd.append("--engine.experimental")
        cmd.append("--rbuilder.config=" + flashbots_rbuilder.MEV_FILE_PATH_ON_CONTAINER)
        files[
            flashbots_rbuilder.MEV_BUILDER_MOUNT_DIRPATH_ON_SERVICE
        ] = flashbots_rbuilder.MEV_BUILDER_FILES_ARTIFACT_NAME
        env_vars.update(
            {
                "CL_ENDPOINT": "http://cl-{0}-{1}-{2}:{3}".format(
                    participant_index + 1,
                    cl_client_name,
                    constants.EL_TYPE.reth_builder,
                    lighthouse.BEACON_HTTP_PORT_NUM,
                ),
            }
        )

    config_args = {
        "image": image,
        "ports": used_ports,
        "public_ports": public_ports,
        "cmd": cmd,
        "files": files,
        "private_ip_address_placeholder": constants.PRIVATE_IP_ADDRESS_PLACEHOLDER,
        "env_vars": env_vars | participant.el_extra_env_vars,
        "labels": shared_utils.label_maker(
            client=constants.EL_TYPE.reth,
            client_type=constants.CLIENT_TYPES.el,
            image=participant.el_image[-constants.MAX_LABEL_LENGTH :],
            connected_client=cl_client_name,
            extra_labels=participant.el_extra_labels,
            supernode=participant.supernode,
        ),
        "tolerations": tolerations,
        "node_selectors": node_selectors,
    }

    if participant.el_min_cpu > 0:
        config_args["min_cpu"] = participant.el_min_cpu
    if participant.el_max_cpu > 0:
        config_args["max_cpu"] = participant.el_max_cpu
    if participant.el_min_mem > 0:
        config_args["min_memory"] = participant.el_min_mem
    if participant.el_max_mem > 0:
        config_args["max_memory"] = participant.el_max_mem
    return ServiceConfig(**config_args)


def new_reth_launcher(
    el_cl_genesis_data, jwt_file, network, builder_type=False, mev_params=None
):
    return struct(
        el_cl_genesis_data=el_cl_genesis_data,
        jwt_file=jwt_file,
        network=network,
        builder_type=builder_type,
        mev_params=mev_params,
    )
