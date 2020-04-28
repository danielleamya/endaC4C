
logspout:
  labels:
    - logspout.exclude=true
  log_opt:
    max-size: "1G"
    max-file: "3"
  image: docker.worldwidestreams.io/wws/logspout:v19.03.07-1504
  restart: on-failure
  environment:
    - ROUTE_URIS=fluentd-tcp://${PRIVATE_IP}:24224
    - EXCLUDE_LABEL=logspout.exclude
    - ELASTICSEARCH_HOST=${PRIVATE_IP}
    - ELASTICSEARCH_PORT=9200
    - EXTERNAL_ELASTICSEARCH_HOST=${PRIVATE_IP}
    - EXTERNAL_ELASTICSEARCH_PORT=9201
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
  mem_limit: 10000000000

fluentd:
  labels:
    - logspout.exclude=true
  log_opt:
    max-size: "1G"
    max-file: "3"
  image: docker.worldwidestreams.io/wws/fluentd:v19.03.07-1504
  environment:
    - FLUENTD_CONF=fluent_double_output.conf  # set this to 'fluent_old_single_output.conf' to feed a single elasticsearch, or 'fluent_double_output.conf' to feed an internal and external elasticsearch
    - RETHINKDB_TCP_ADDR=${PRIVATE_IP}
    - ES_PORT_9200_TCP_ADDR=${PRIVATE_IP}
    - EXTERNAL_USER_ES_TCP_ADDR=${PRIVATE_IP}
    - ELASTICSEARCH_HOST=${PRIVATE_IP}
    - ELASTICSEARCH_PORT=9200 
    - EXTERNAL_ELASTICSEARCH_HOST=${PRIVATE_IP}
    - EXTERNAL_ELASTICSEARCH_PORT=9201         
  ports:
    - "24224:24224"
  mem_limit: 10000000000

elasticsearch:
  labels:
    - logspout.exclude=true
  log_opt:
    max-size: "1G"
    max-file: "3"
  image: elasticsearch:6.5.1
  ports:
    - "9300:9300"
    - "9200:9200"
  volumes:
    - esdata:/usr/share/elasticsearch/data
  environment:
    - discovery.type=single-node
    - cluster.name=docker-cluster
    - bootstrap.memory_lock=false
    - "ES_JAVA_OPTS=-Xms512m -Xmx512m"

kibana:
  labels:
    - logspout.exclude=true
  log_opt:
    max-size: "1G"
    max-file: "3"
  image: docker.worldwidestreams.io/wws/kibana:v19.03.07-1504
  ports:
    - "5601:5601"
  environment:
    - ELASTICSEARCH_URL=http://${PRIVATE_IP}:9200
    - SERVER_BASEPATH=/admin/logging
    - ELASTICSEARCH_HOST=${PRIVATE_IP}
    - ELASTICSEARCH_PORT=9200    
  mem_limit: 10000000000

externalelasticsearch:
  labels:
    - logspout.exclude=true
  log_opt:
    max-size: "1G"
    max-file: "3"
  image: elasticsearch:6.5.1
  ports:
    - "9301:9300"
    - "9201:9200"
  volumes:
    - esexternaldata:/usr/share/elasticsearch/data
  environment:
    - discovery.type=single-node
    - cluster.name=docker-cluster
    - bootstrap.memory_lock=false
    - "ES_JAVA_OPTS=-Xms512m -Xmx512m"


external_kibana:
  labels:
    - logspout.exclude=true
  log_opt:
    max-size: "1G"
    max-file: "3"
  image: docker.worldwidestreams.io/wws/kibana:v19.03.07-1504
  ports:
    - "5602:5601"
  environment:
    - ELASTICSEARCH_URL=http://${PRIVATE_IP}:9201
    - SERVER_BASEPATH=/logging
    - ELASTICSEARCH_HOST=${PRIVATE_IP}
    - ELASTICSEARCH_PORT=9201       
  mem_limit: 10000000000

dispatcher:
  labels:
    - Process=dispatcher
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/deployment:v19.03.07-1504
  links:
    - broker
  extra_hosts:
    - "registry:${PRIVATE_IP}"
    - "stream_registry:${PRIVATE_IP}"
  #alternative approach to set environment
  #env_file: dispatch.env
  environment:
    CONFIG_OVERRIDE: "{LOGGING: {LEVEL: error, CONFIG: true}}"
    WWS_DISPATCHER_ASYNC_EXECUTOR: "false"
    WWS_DISPATCHER_RPC_TIMEOUT: "60"
    #WWS_SITE_ID: 
    WWS_DISPATCHER_SITE_NAME: "local_1"
  command: bash -c "lttng create && python src/dispatcher/dispatcher.py"
  mem_limit: 10000000000

registry:
  labels:
    - Process=registry
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/registry:v19.03.07-1504
  volumes:
    - data:/data
  ports:
    - "28015:28015"
    - "29015:29015"
    - "8085:8080"
  mem_limit: 10000000000
  command: rethinkdb --bind all --no-update-check --canonical-address ${PRIVATE_IP}:29015
    

# deployer served over json-rpc over amqp
# This API is used by the gateway
deployer:
  labels:
    - Process=deployer
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/deployment:v19.03.07-1504
  extra_hosts:
    - "broker:${PRIVATE_IP}"
    - "registry:${PRIVATE_IP}"
    - "stream_registry:${PRIVATE_IP}"
  environment:
    CONFIG_OVERRIDE: "{LOGGING: {LEVEL: info, CONFIG: true}}"
    WWS_RTMP_SERVER_URL: rtmp://${PRIVATE_IP}:1935
    #used by rectify
    WWS_BROKER_RPC_URL: amqp://instadash:instadash!@${PRIVATE_IP}:5672/%2ftest
    WWS_BROKER_DATA_URL: amqp://instadash:instadash!@${PRIVATE_IP}:5672/%2ftest
    WWS_DEPLOYER_REUSE_OPERATORS: "false" #this variable is boolean and compose expects strings
    WWS_DEPLOYER_DEFAULT_SITE: local_1
  command: bash -c "lttng create && python src/rpc.py"
  mem_limit: 10000000000

# deployer served over REST api
# This API is used by the deployer cli
# this container serves also the authentication stub to generate jwt tokens for the cli
deploy_rest:
  labels:
    - Process=deploy_rest
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/deployment:v19.03.07-1504
  extra_hosts:
    - "broker:${PRIVATE_IP}"
    - "registry:${PRIVATE_IP}"
    - "stream_registry:${PRIVATE_IP}"
  ports:
    - "8004:8004"
  environment:
    CONFIG_OVERRIDE: "{LOGGING: {LEVEL: info, CONFIG: true}}"
    WWS_RTMP_SERVER_URL: rtmp://${PRIVATE_IP}:1935
    WWS_DEPLOYER_DEFAULT_SITE: local_1
  command: bash -c "lttng create && python src/rest.py"
  mem_limit: 10000000000

gateway:
  labels:
    - Process=gateway
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/gateway:v19.03.07-1504
  extra_hosts:
    - "broker:${PRIVATE_IP}"
  environment:
    - NODE_ENV=docker_local
    - STREAM_REGISTRY=${PRIVATE_IP}
    - STREAM_BRIDGE_URL=http://${PRIVATE_IP}:9998
    - DEPLOYER_REST_URL=http://${PRIVATE_IP}:8004
  ports:
    - "8080:8080"
    - "9228:9228"
    - "9228:9228/udp"
  command: bash -c "cd /wws/gateway; npm run startDebug"
  mem_limit: 10000000000

stream_registry:
  labels:
    - Process=stream_registry
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/stream_registry:v19.03.07-1504
  links:
    - registry
  ports:
    - "3000:3000"
  environment:
    - NODE_ENV=docker_streamRegistry
  command:
    ["./wait-for-it.sh", "registry:28015", "-t","300", "--", "node", "registry.js"]
broker:
  labels:
    - Process=broker
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/broker:v19.03.07-1504
  environment:
    - RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS=
  ports:
    - "5671:5671"
    - "5672:5672"
    - "15672:15672"
    - "15674:15674"
    - "1883:1883"
  mem_limit: 10000000000
deploygraph:
  labels:
    - Process=deploygraph
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/deployment:v19.03.07-1504
  extra_hosts:
    - "registry:${PRIVATE_IP}"
    - "broker:${PRIVATE_IP}"
    - "stream_registry:${PRIVATE_IP}"
    - "janus_public:${PRIVATE_IP}"
  ports:
    - "8001:8001"
  environment:
    - WWS_JANUS_PUBLIC=janus://${PUBLIC_HOSTNAME}:8089/janus
    - WWS_GATEWAY_PUBLIC=http://${PUBLIC_HOSTNAME}:8080
    - WWS_RTMP_PUBLIC_URL=rtmps://${PUBLIC_HOSTNAME}
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
  command: bin/graph
  mem_limit: 10000000000


postgres:
  labels:
    - Process=postgres
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: postgres:10.1
  ports:
    - "5432:5432"
  environment:
    POSTGRES_USER: instadash
    POSTGRES_PASSWORD: Instadash!
  mem_limit: 10000000000

resourcedb:
  labels:
    - Process=resourcedb
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/redis:v19.03.07-1504
  ports:
    - "6380:6379"
  mem_limit: 10000000000
node_processor:
  labels:
    - Process=node_processor
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/node_processor:v19.03.07-1504
  #links:
  #  - resourcedb
  extra_hosts:
    resourcedb : ${PRIVATE_IP}
  ports:
    - "9220:9220"
    - "9220:9220/udp"
  environment:
    - WWS_NODE_PROCESSOR_BROKER_DATA_USER=node_processor
    - WWS_NODE_PROCESSOR_BROKER_DATA_PASSWORD=instadash!
    - WWS_NODE_PROCESSOR_BROKER_DATA_HOST=${PRIVATE_IP}
    - WWS_NODE_PROCESSOR_BROKER_DATA_PORT=5672
    - WWS_NODE_PROCESSOR_BROKER_DATA_VHOST=/test
    - WWS_NODE_PROCESSOR_BROKER_DATA_EXCHANGE=data
    - WWS_NODE_PROCESSOR_BROKER_RPC_USER=node_processor
    - WWS_NODE_PROCESSOR_BROKER_RPC_PASSWORD=instadash!
    - WWS_NODE_PROCESSOR_BROKER_RPC_HOST=${PRIVATE_IP}
    - WWS_NODE_PROCESSOR_BROKER_RPC_PORT=5672
    - WWS_NODE_PROCESSOR_BROKER_RPC_VHOST=/test
    - WWS_NODE_PROCESSOR_BROKER_RPC_EXCHANGE=rpc
    - WWS_NODE_PROCESSOR_BROKER_RPC_QUEUE_NAME=wws/node_processor
    - WWS_NODE_PROCESSOR_BROKER_NEURALTALK_USER=node_processor
    - WWS_NODE_PROCESSOR_BROKER_NEURALTALK_PASSWORD=instadash!
    - WWS_NODE_PROCESSOR_BROKER_NEURALTALK_HOST=${PRIVATE_IP}
    - WWS_NODE_PROCESSOR_BROKER_NEURALTALK_PORT=5672
    - WWS_NODE_PROCESSOR_BROKER_NEURALTALK_VHOST=/test
    - WWS_NODE_PROCESSOR_BROKER_NEURALTALK_QUEUE_NAME=neuraltalk
    - WWS_NODE_PROCESSOR_BROKER_MATE_PARSER_USER=node_processor
    - WWS_NODE_PROCESSOR_BROKER_MATE_PARSER_PASSWORD=instadash!
    - WWS_NODE_PROCESSOR_BROKER_MATE_PARSER_HOST=${PRIVATE_IP}
    - WWS_NODE_PROCESSOR_BROKER_MATE_PARSER_PORT=5672
    - WWS_NODE_PROCESSOR_BROKER_MATE_PARSER_VHOST=/test
    - WWS_NODE_PROCESSOR_BROKER_MATE_PARSER_QUEUE_NAME=mate_parser
    - WWS_NODE_PROCESSOR_REDIS_HOST=${PRIVATE_IP}
    - WWS_NODE_PROCESSOR_REDIS_PORT=6380
    - WWS_NODE_PROCESSOR_PG_USER=instadash
    - WWS_NODE_PROCESSOR_PG_PASSWORD=Instadash!
    - WWS_NODE_PROCESSOR_PG_DATABASE=instadash
    - WWS_NODE_PROCESSOR_PG_HOST=${PRIVATE_IP}
    - WWS_NODE_PROCESSOR_PG_PORT=5432
    - WWS_NODE_PROCESSOR_MONITOR_HOST=${PRIVATE_IP}
    - WWS_NODE_PROCESSOR_MONITOR_PORT=5555
    - WWS_NODE_PROCESSOR_MONITOR_SERVICE_NAME=node_processor
    - WWS_NODE_PROCESSOR_COLLECT_ASYNC_STACKTRACES=false
    - WWS_NODE_PROCESSOR_LOG_LEVEL=info
    - GST_DEBUG=1
  command: bash -c "cd /wws/node_processor ; npm run startDebug"
  mem_limit: 10000000000

python_processor:
  labels:
    - Process=python_processor
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/python_processor:v19.03.07-1504
  links:
    - broker
    #- riemann
  command: bash -c "cd /wws/python_processor; ./bin/run_python_processor.sh"
  mem_limit: 10000000000
gevent_processor:
  labels:
    - Process=gevent_processor
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/deployment:v19.03.07-1504
  links:
    - broker
    #- riemann
  extra_hosts:
    - "registry:${PRIVATE_IP}"
    - "stream_registry:${PRIVATE_IP}"
  environment:
    CONFIG_OVERRIDE: "{LOGGING: {LEVEL: info}}"
  command: bash -c "lttng create && python src/processor/rpc.py"
  mem_limit: 10000000000
dashboard:
  labels:
    - Process=dashboard
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/dashboard:v19.03.07-1504
  extra_hosts:
    - "stream_registry:${PRIVATE_IP}"
  environment:
    - NODE_ENV=docker_local
    - GATEWAY_URL=http://${PRIVATE_IP}:8080
    - STREAM_BRIDGE_URL=http://${PRIVATE_IP}:9998
    - CLEAN_DB_ON_STARTUP=false
    - ELASTICSEARCH_URL=http://${PRIVATE_IP}:9200
    - EXTERNAL_ELASTICSEARCH_URL=http://${PRIVATE_IP}:9201
    - DEPLOYERGRAPH_URL=http://${PRIVATE_IP}:8001
    - STOMP_TIMEOUT=30000
  ports:
    - "9009:9009"
    - "9222:9222"
    - "9222:9222/udp"
  command: 
    bash -c "cd /wws/dashboard; npm run startDebug"
  mem_limit: 10000000000
streambridge:
  labels:
    - Process=streambridge
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/bridge:2019-02-08-lode-1
  links:
    - broker
    - stream_registry
  environment:
    - NODE_ENV=docker_local
    - ENABLE_AUTH=false
    - ENABLE_BASIC_AUTH=false
    - BASE_OIDC_URL=https://sec.worldwidestreams.io/auth/realms/wws
    - OIDC_CLIENT_ID=
    - REVERSE_PROXY_PATH=/streambridge
    - STREAM_REGISTRY_IP_PORT=${PRIVATE_IP}:3000
    - STREAM_BRIDGE_AMQP_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:5672
    - STREAM_BRIDGE_MQTT_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:1883
    - STREAM_BRIDGE_STOMP_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:15674
    - STREAM_BRIDGE_STOMPS_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:443
    - STREAM_BRIDGE_HTTP_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:9998
    - STREAM_BRIDGE_HTTPS_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:8999
    - STREAM_BRIDGE_KAFKA_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:9092
    - STREAM_BRIDGE_KAFKA_CONNECT_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:8083
    - STREAM_BRIDGE_RTMP_PUBLIC_URL=rtmp://${PUBLIC_HOSTNAME}:1935
    - STREAM_BRIDGE_RTMP_LOCAL_URL=rtmp://${PRIVATE_IP}:1935/bridge
    - STREAM_BRIDGE_RTMPS_PUBLIC_URL=rtmps://${PUBLIC_HOSTNAME}/bridge
    - STREAM_BRIDGE_RTMPS_LOCAL_URL=rtmps://${PRIVATE_IP}:1935/bridge
    - STREAM_BRIDGE_WEBRTC_PUBLIC_URL=janus://${PUBLIC_HOSTNAME}:8089/janus
  ports:
    - "9999:9999"
    - "9227:9227"
    - "9227:9227/udp"
  command: bash -c "npm run startDebug"
  mem_limit: 10000000000
bridge:
  labels:
    - Process=bridge
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/bridge:v19.03.07-1504
  links:
    - broker
    - stream_registry
  environment:
    - NODE_ENV=docker_local
    - ENABLE_AUTH=false
    - ENABLE_BASIC_AUTH=false
    - BASE_OIDC_URL=https://sec.worldwidestreams.io/auth/realms/wws
    - OIDC_CLIENT_ID=
    - REVERSE_PROXY_PATH=/streambridge
    - STREAM_REGISTRY_IP_PORT=${PRIVATE_IP}:3000
    - STREAM_BRIDGE_AMQP_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:5672
    - STREAM_BRIDGE_MQTT_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:1883
    - STREAM_BRIDGE_STOMP_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:15674
    - STREAM_BRIDGE_STOMPS_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:443
    - STREAM_BRIDGE_HTTP_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:9998
    - STREAM_BRIDGE_HTTPS_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:8999
    - STREAM_BRIDGE_KAFKA_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:9092
    - STREAM_BRIDGE_KAFKA_CONNECT_PUBLIC_IP_PORT=${PUBLIC_HOSTNAME}:8083
    - STREAM_BRIDGE_RTMP_PUBLIC_URL=rtmp://${PUBLIC_HOSTNAME}:1935
    - STREAM_BRIDGE_RTMP_LOCAL_URL=rtmp://${PRIVATE_IP}:1935/bridge
    - STREAM_BRIDGE_RTMPS_PUBLIC_URL=rtmps://${PUBLIC_HOSTNAME}/bridge
    - STREAM_BRIDGE_RTMPS_LOCAL_URL=rtmps://${PRIVATE_IP}:1935/bridge
    - STREAM_BRIDGE_WEBRTC_PUBLIC_URL=janus://${PUBLIC_HOSTNAME}:8089/janus
  ports:
    - "9998:9998"
    - "9226:9226"
    - "9226:9226/udp"
  command: bash -c "npm run startDebug"
  mem_limit: 10000000000
proxy:
  labels:
    - Process=proxy
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/proxy:v19.03.07-1504
  ports:
    - "80:80"
    - "443:443"
    - "9000:80"
    - "8999:443"
  extra_hosts:
    - "janus:${PRIVATE_IP}"
    - "broker:${PRIVATE_IP}"
    - "mediaproxy:${PRIVATE_IP}"
    - "rtmp_server:${PRIVATE_IP}"
    - "webapp:${PRIVATE_IP}"
    - "dashboard:${PRIVATE_IP}"
    - "impact_bridge:${PRIVATE_IP}"
    - "host_ip:${PRIVATE_IP}"
    - "gateway:${PRIVATE_IP}"
    - "bridge:${PRIVATE_IP}"
    - "deploygraph:${PRIVATE_IP}"
    - "stream_registry:${PRIVATE_IP}"

  mem_limit: 10000000000

mediaserver:
  labels:
    - Process=mediaserver
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/mediaserver:v19.03.07-1504
  ports:
    - "1935:1935"   #RTMP port
    - "8035:8035"   #RTMP statistics, static files
  command: bash -c '/usr/local/nginx/sbin/nginx -g "daemon off;"'
  mem_limit: 10000000000
gstreamer_processor:
  labels:
    - Process=gstreamer_processor
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/gstreamer_processor:v19.03.07-1504
  links:
    - broker
  extra_hosts:
    - "rtmp_server:${PRIVATE_IP}"
    - "rtsp_server:${PRIVATE_IP}"
  ports:
    - "8000:8000"
  environment:
    CONFIG_OVERRIDE: "{LOGGING: {LEVEL: debug}}"
    WWS_HTTP_IP: ${PRIVATE_IP}
    WWS_HTTP_PORT: 8000
    WWS_HTTP_PUBLIC_PREFIX: http://${PUBLIC_HOSTNAME}:8000/
    WWS_BROKER_DATA_URL: amqp://instadash:instadash!@${PRIVATE_IP}:5672/%2ftest
    WWS_BROKER_RPC_URL: amqp://instadash:instadash!@${PRIVATE_IP}:5672/%2ftest
    WWS_BROKER_RPC_QUEUE: gstreamer_processor
    WWS_LOG_LEVEL: info
  command: bash -c "bin/run.sh"
  mem_limit: 10000000000

tensorflow_processor:
  labels:
    - Process=tensorflow_processor
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/tensorflow_processor:v19.03.07-1504
  extra_hosts:
    - "broker:${PRIVATE_IP}"
  environment:
    WWS_BROKER_RPC_QUEUE: "wws/tensorflow_processor"
    ZMQ_SERVICE_SOCKET: "tcp://localhost:5566"
    ZMQ_SERVICE_TIMEOUT: 4500
    ZMQ_SERVICE_RETRIES: 5
  command: bash -c "python src/wws/rpc.py"
  mem_limit: 10000000000

#test video sources
#bristol video set
rtsp_data_bristol:
  labels:
    - Process=rtsp_data_bristol
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/bristol_footage:3
  volumes:
    - /rtsp_data/bio
  command: /bin/true
  mem_limit: 10000000000

#standries video set
#rtsp_data_st_andries:
#  image: docker.worldwidestreams.io/wws/st_andries_footage:3
#  volumes:
#    - /rtsp_data/st-andries
#  command: /bin/true
#  mem_limit: 10000000000

#rtsp_data_st_andries2:
#  image: docker.worldwidestreams.io/footage/record-ua
#  volumes:
#    - /rtsp_data/recorcd-ua
#  command: /bin/true
#  mem_limit: 10000000000

#rtsp_data_st_andries3:
#  image: docker.worldwidestreams.io/wws_data/record-ua-1002
#  volumes:
#    - /rtsp_data/record-ua-1002
#  command: /bin/true
#  mem_limit: 10000000000

rtsp_data_st_andries4:
  labels:
    - Process=rtsp_data_st_andries4
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws_data/st_andries_4:1
  volumes:
    - /rtsp_data/st-andries-4
  command: /bin/true
  mem_limit: 10000000000

rtsp_data_fitelab:
  labels:
    - Process=rtsp_data_fitelab
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws_data/fitelab_footage:1
  volumes:
    - /rtsp_data/fitelab
  command: /bin/true
  mem_limit: 10000000000


rtsp_server:
  labels:
    - Process=rtsp_server
    - User=jenkins
  log_opt:
    max-size: "10M"
    max-file: "3"
    env: SITE_NAME,HOST_MACHINE
    labels: Process,User
  image: docker.worldwidestreams.io/wws/gstreamer_processor:v19.03.07-1504
  volumes_from:
    - rtsp_data_bristol:ro
      #- rtsp_data_st_andries:ro
      #- rtsp_data_st_andries2:ro
      #- rtsp_data_st_andries3:ro
    - rtsp_data_st_andries4:ro
    - rtsp_data_fitelab:ro
  ports:
    - "8554:8554"
  command: python ./tools/rtsp-server/rtsp-server.py /rtsp_data/bio bio /rtsp_data/st-andries st_andries /rtsp_data/st-andries-4 st_andries_4 /rtsp_data/fitelab fitelab
  mem_limit: 10000000000


