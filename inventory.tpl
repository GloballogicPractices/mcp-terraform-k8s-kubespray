[all]
${master_ip}
${node_ip}
${etcd_ip}

[kube-master]
${master_ip}

[kube-node]
${node_ip}

[etcd]
${etcd_ip}

[k8s-cluster:children]
kube-node
kube-master

[all:vars]
ansible_ssh_private_key_file = ${key_path}
ansible_ssh_user = centos
