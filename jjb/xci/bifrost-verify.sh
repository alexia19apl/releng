#!/bin/bash
# SPDX-license-identifier: Apache-2.0
##############################################################################
# Copyright (c) 2016 Ericsson AB and others.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################
set -o errexit
set -o nounset
set -o pipefail

git clone https://gerrit.opnfv.org/gerrit/releng-xci $WORKSPACE/releng-xci

cd $WORKSPACE
git fetch $PROJECT_REPO $GERRIT_REFSPEC && sudo git checkout FETCH_HEAD

# combine opnfv and upstream scripts/playbooks
/bin/cp -rf $WORKSPACE/releng-xci/xci/infra/bifrost/* $WORKSPACE/

cd $WORKSPACE/releng-xci
cat > bifrost_test.sh<<EOF
#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

cd ~/bifrost
# set path for XCI repository
export XCI_PATH=~/bifrost/releng-xci

# provision 3 VMs; xcimaster, controller, and compute
./scripts/bifrost-provision.sh | ts

sudo -H -E virsh list
EOF
chmod a+x bifrost_test.sh

# Fix up distros
case ${DISTRO} in
	xenial) VM_DISTRO=ubuntu ;;
	centos7) VM_DISTRO=centos ;;
	*suse*) VM_DISTRO=opensuse ;;
esac

export XCI_BUILD_CLEAN_VM_OS=false
export XCI_UPDATE_CLEAN_VM_OS=true

./xci/scripts/vm/start-new-vm.sh $VM_DISTRO

rsync -a -e "ssh -F $HOME/.ssh/${VM_DISTRO}-xci-vm-config" $WORKSPACE/ ${VM_DISTRO}_xci_vm:~/bifrost

ssh -F $HOME/.ssh/${VM_DISTRO}-xci-vm-config ${VM_DISTRO}_xci_vm "cd ~/bifrost/releng-xci && ./bifrost_test.sh"
