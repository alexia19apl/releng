#!/bin/bash
##############################################################################
# Copyright (c) 2017 Huawei Technologies Co.,Ltd and others.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

#set -e
[[ $GERRIT_REFSPEC_DEBUG == true ]] && redirect="/dev/stdout" || redirect="/dev/null"
BOTTLENECKS_IMAGE=opnfv/bottlenecks
REPORT="True"

RELENG_REPO=${WORKSPACE}/releng
[ -d ${RELENG_REPO} ] && rm -rf ${RELENG_REPO}
git clone https://gerrit.opnfv.org/gerrit/releng ${RELENG_REPO} >${redirect}

YARDSTICK_REPO=${WORKSPACE}/yardstick
[ -d ${YARDSTICK_REPO} ] && rm -rf ${YARDSTICK_REPO}
git clone https://gerrit.opnfv.org/gerrit/yardstick ${YARDSTICK_REPO} >${redirect}

OPENRC=/tmp/admin_rc.sh
OS_CACERT=/tmp/os_cacert

BOTTLENECKS_CONFIG=/tmp
KUBESTONE_TEST_DIR=/home/opnfv/bottlenecks/testsuites/kubestone/testcases

# Pulling Bottlenecks docker and passing environment variables
echo "INFO: pulling Bottlenecks docker ${DOCKER_TAG}"
docker pull opnfv/bottlenecks:${DOCKER_TAG} >$redirect

opts="--privileged=true -id"
envs="-e INSTALLER_TYPE=${INSTALLER_TYPE} -e INSTALLER_IP=${INSTALLER_IP} \
      -e NODE_NAME=${NODE_NAME} -e EXTERNAL_NET=${EXTERNAL_NETWORK} \
      -e BRANCH=${BRANCH} -e GERRIT_REFSPEC_DEBUG=${GERRIT_REFSPEC_DEBUG} \
      -e BOTTLENECKS_DB_TARGET=${BOTTLENECKS_DB_TARGET} -e PACKAGE_URL=${PACKAGE_URL} \
      -e DEPLOY_SCENARIO=${DEPLOY_SCENARIO} -e BUILD_TAG=${BUILD_TAG}"
docker_volume="-v /var/run/docker.sock:/var/run/docker.sock -v /tmp:/tmp"

cmd="docker run ${opts} ${envs} --name bottlenecks-load-master ${docker_volume} opnfv/bottlenecks:${DOCKER_TAG} /bin/bash"
echo "BOTTLENECKS INFO: running docker run commond: ${cmd}"
${cmd} >$redirect
sleep 5

# Run test suite
if [[ $SUITE_NAME == *posca* ]]; then
    POSCA_SCRIPT=/home/opnfv/bottlenecks/testsuites/posca
    sudo rm -f ${OPENRC}

    if [[ -f ${OPENRC} ]]; then
        echo "BOTTLENECKS INFO: openstack credentials path is ${OPENRC}"
        cat ${OPENRC}
    else
        echo "BOTTLENECKS ERROR: couldn't find openstack rc file: ${OPENRC}, please check if the it's been properly provided."
        exit 1
    fi

    # Finding and crearting POD description files from different deployments
    ssh_options="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

    if [ "$INSTALLER_TYPE" == "fuel" ]; then
        echo "Fetching id_rsa file from jump_server $INSTALLER_IP..."
        sshpass -p r00tme sudo scp $ssh_options root@${INSTALLER_IP}:~/.ssh/id_rsa ${BOTTLENECKS_CONFIG}/id_rsa
    fi

    if [ "$INSTALLER_TYPE" == "apex" ]; then
        echo "Fetching id_rsa file from jump_server $INSTALLER_IP..."
        sudo scp $ssh_options stack@${INSTALLER_IP}:~/.ssh/id_rsa ${BOTTLENECKS_CONFIG}/id_rsa
    fi

    set +e

    sudo -H pip install virtualenv

    cd ${RELENG_REPO}/modules
    sudo virtualenv venv
    source venv/bin/activate
    sudo -H pip install -e ./ >/dev/null
    sudo -H pip install netaddr

    if [[ ${INSTALLER_TYPE} == fuel ]]; then
        options="-u root -p r00tme"
    elif [[ ${INSTALLER_TYPE} == apex ]]; then
        options="-u stack -k /root/.ssh/id_rsa"
    else
        echo "Don't support to generate pod.yaml on ${INSTALLER_TYPE} currently."
    fi

    deactivate

    sudo rm -rf ${RELENG_REPO}/modules/venv
    sudo rm -rf ${RELENG_REPO}/modules/opnfv.egg-info

    set -e

    cd ${WORKSPACE}

    if [ -f ${BOTTLENECKS_CONFIG}/pod.yaml ]; then
        echo "FILE: ${BOTTLENECKS_CONFIG}/pod.yaml:"
        cat ${BOTTLENECKS_CONFIG}/pod.yaml
    else
        echo "ERROR: cannot find file ${BOTTLENECKS_CONFIG}/pod.yaml. Please check if it is existing."
        sudo ls -al ${BOTTLENECKS_CONFIG}
    fi

    # Running test cases through Bottlenecks docker
    if [[ $SUITE_NAME == posca_stress_traffic ]]; then
        TEST_CASE=posca_factor_system_bandwidth
    elif [[ $SUITE_NAME == posca_stress_ping ]]; then
        TEST_CASE=posca_factor_ping
    else
        TEST_CASE=$SUITE_NAME
    fi
    testcase_cmd="docker exec bottlenecks-load-master python ${POSCA_SCRIPT}/../run_testsuite.py testcase $TEST_CASE $REPORT"
    echo "BOTTLENECKS INFO: running test case ${TEST_CASE} with report indicator: ${testcase_cmd}"
    ${testcase_cmd} >$redirect
elif [[ $SUITE_NAME == *kubestone* ]]; then
    if [[ $SUITE_NAME == kubestone_deployment_capacity ]]; then
        TEST_CASE=${KUBESTONE_TEST_DIR}/deployment_capacity.yaml
    fi
    testcase_cmd="docker exec bottlenecks-load-master python ${KUBESTONE_TEST_DIR}/../stress_test.py -c $TEST_CASE"
    echo "BOTTLENECKS INFO: running test case ${TEST_CASE} with report indicator: ${testcase_cmd}"
    ${testcase_cmd} >$redirect
fi
