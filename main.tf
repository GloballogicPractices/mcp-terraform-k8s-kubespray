provider "openstack" {
  user_name = "${var.openstack_user_name}"
  tenant_name = "${var.openstack_tenant_name}"
  password  = "${var.openstack_password}"
  auth_url  = "${var.openstack_auth_url}"
  insecure = "true"
}

resource "openstack_compute_secgroup_v2" "securitygroup" {
  count = "${var.separate_etcd ? length(var.component_name) : length(var.component_name) - 1 }"
  name = "${var.prefix}-SG-${lookup(var.component_name, count.index)}"
  description = "Security group for the ${var.prefix} ${lookup(var.component_name, count.index)} instances"
  
  rule {
    from_port   = 1
    to_port     = 65535
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }
  rule {
    from_port = 1
    to_port = 65535
    ip_protocol = "tcp"
    cidr = "::/0"
  }
}

resource "openstack_compute_keypair_v2" "keypair" {
  name = "${var.prefix}-Key"
}

resource "local_file" "private-key" {
    content     = "${openstack_compute_keypair_v2.keypair.private_key }"
    filename = "${path.module}/${var.prefix}-Key.pem"

    provisioner "local-exec" {
    	command = "chmod 600 ${path.module}/${var.prefix}-Key.pem"
    }
}

resource "openstack_compute_instance_v2" "MasterInstance" {
  count = "${var.master_cluster_size}"
  name  = "${var.prefix}-VM-${lookup(var.component_name, 0)}-${count.index + 1}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.keypair.name}"
  security_groups = ["${var.prefix}-SG-${lookup(var.component_name, 0)}"]
  image_name = "${var.image}"
  network {
    name = "${var.network}"
  }
  block_device {
    uuid		  = "${var.image_id}"
    source_type           = "image"
    volume_size           = "${var.root_volume}"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  connection={
    type 		= "ssh"
    user 		= "centos"
    private_key 	= "${openstack_compute_keypair_v2.keypair.private_key }"
    }

  provisioner "file" {
    source      = "centos.repo"
    destination = "/tmp/centos.repo"
  }

}

resource "openstack_compute_instance_v2" "EtcdInstance" {
  count = "${var.separate_etcd ? var.etcd_cluster_size : 0 }"
  name  = "${var.prefix}-VM-${lookup(var.component_name, 2)}-${count.index + 1}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.keypair.name}"
  security_groups = ["${var.prefix}-SG-${lookup(var.component_name, 2)}"]
  image_name = "${var.image}"
  network {
    name = "${var.network}"
  }
  block_device {
    uuid                  = "${var.image_id}"
    source_type           = "image"
    volume_size           = "${var.root_volume}"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  connection={
    type                = "ssh"
    user                = "centos"
    private_key         = "${openstack_compute_keypair_v2.keypair.private_key }"
    }

  provisioner "file" {
    source      = "centos.repo"
    destination = "/tmp/centos.repo"
  }

}

resource "openstack_compute_instance_v2" "NodeInstance" {
  count = "${var.node_cluster_size}"
  name  = "${var.prefix}-VM-${lookup(var.component_name, 1)}-${count.index + 1}"
  flavor_name = "${var.flavor}"
  key_pair = "${openstack_compute_keypair_v2.keypair.name}"
  security_groups = ["${var.prefix}-SG-${lookup(var.component_name, 1)}"]
  image_name = "${var.image}"
  network {
    name = "${var.network}"
  }
  block_device {
    uuid                  = "${var.image_id}"
    source_type           = "image"
    volume_size           = "${var.root_volume}"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  connection={
    type                = "ssh"
    user                = "centos"
    private_key         = "${openstack_compute_keypair_v2.keypair.private_key }"
    }

  provisioner "file" {
    source      = "centos.repo"
    destination = "/tmp/centos.repo"
  }

}

resource "openstack_networking_floatingip_v2" "master_floating_ip" {
  count = "${var.master_cluster_size}"
  pool = "${var.flotingip_pool}"
}

resource "openstack_networking_floatingip_v2" "node_floating_ip" {
  count = "${var.node_cluster_size}"
  pool = "${var.flotingip_pool}"
}

resource "openstack_networking_floatingip_v2" "etcd_floating_ip" {
  count = "${var.separate_etcd ? var.etcd_cluster_size : 0 }"
  pool = "${var.flotingip_pool}"
}

resource "openstack_compute_floatingip_associate_v2" "master_floting_ip" {
  count = "${var.master_cluster_size}"
  floating_ip = "${element(openstack_networking_floatingip_v2.master_floating_ip.*.address, count.index)}"
  instance_id = "${element(openstack_compute_instance_v2.MasterInstance.*.id, count.index)}"

  connection={
    host	= "${element(openstack_compute_instance_v2.MasterInstance.*.access_ip_v4, count.index)}"
    type        = "ssh"
    user        = "centos"
    private_key         = "${openstack_compute_keypair_v2.keypair.private_key }"
    }

  provisioner "remote-exec" {
    inline = [
    "sudo mv /tmp/centos.repo /etc/yum.repos.d/centos.repo",
    "echo proxy=http://10.144.106.132:8678 | sudo tee -a /etc/yum.conf",
    "sudo yum -y install wget",
    "export http_proxy=http://10.144.106.132:8678",
    "wget http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm",
    "sudo rpm -ivh epel-release-latest-7.noarch.rpm",
    "wget http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.68-1.el7.noarch.rpm",
    "sudo yum-config-manager --disable extras",
    "sudo yum makecache",
    "sudo yum localinstall container-selinux-2.68-1.el7.noarch.rpm -y"
    ]
  }
}

resource "openstack_compute_floatingip_associate_v2" "node_floting_ip" {
  count = "${var.node_cluster_size}"
  floating_ip = "${element(openstack_networking_floatingip_v2.node_floating_ip.*.address, count.index)}"
  instance_id = "${element(openstack_compute_instance_v2.NodeInstance.*.id, count.index)}"

  connection={
    host        = "${element(openstack_compute_instance_v2.NodeInstance.*.access_ip_v4, count.index)}"
    type        = "ssh"
    user        = "centos"
    private_key         = "${openstack_compute_keypair_v2.keypair.private_key }"
    }

  provisioner "remote-exec" {
    inline = [
    "sudo mv /tmp/centos.repo /etc/yum.repos.d/centos.repo",
    "echo proxy=http://10.144.106.132:8678 | sudo tee -a /etc/yum.conf",
    "sudo yum -y install wget",
    "export http_proxy=http://10.144.106.132:8678",
    "wget http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm",
    "sudo rpm -ivh epel-release-latest-7.noarch.rpm",
    "wget http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.68-1.el7.noarch.rpm",
    "sudo yum-config-manager --disable extras",
    "sudo yum makecache",
    "sudo yum localinstall container-selinux-2.68-1.el7.noarch.rpm -y"
    ]
  }
}

resource "openstack_compute_floatingip_associate_v2" "etcd_floting_ip" {
  count = "${var.separate_etcd ? var.etcd_cluster_size : 0 }"
  floating_ip = "${element(openstack_networking_floatingip_v2.etcd_floating_ip.*.address, count.index)}"
  instance_id = "${element(openstack_compute_instance_v2.EtcdInstance.*.id, count.index)}"

  connection={
    host        = "${element(openstack_compute_instance_v2.EtcdInstance.*.access_ip_v4, count.index)}"
    type        = "ssh"
    user        = "centos"
    private_key         = "${openstack_compute_keypair_v2.keypair.private_key }"
    }

  provisioner "remote-exec" {
    inline = [
    "sudo mv /tmp/centos.repo /etc/yum.repos.d/centos.repo",
    "echo proxy=http://10.144.106.132:8678 | sudo tee -a /etc/yum.conf",
    "sudo yum -y install wget",
    "export http_proxy=http://10.144.106.132:8678",
    "wget http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm",
    "sudo rpm -ivh epel-release-latest-7.noarch.rpm",
    "wget http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.68-1.el7.noarch.rpm",
    "sudo yum-config-manager --disable extras",
    "sudo yum makecache",
    "sudo yum localinstall container-selinux-2.68-1.el7.noarch.rpm -y"
    ]
  }
}

output "master" {
  value = "${openstack_compute_instance_v2.MasterInstance.*.access_ip_v4}"
}

output "node" {
  value = "${openstack_compute_instance_v2.NodeInstance.*.access_ip_v4}"
}

output "etcd" {
  value = "${openstack_compute_instance_v2.EtcdInstance.*.access_ip_v4}"
}

output "keypair" {
  value = "${openstack_compute_keypair_v2.keypair.private_key }"
}


data "template_file" "master_inventory" {
    count = "${var.master_cluster_size}"
    template = "$${ip} ip=$${ip}" 
    vars {
        ip = "${element(openstack_compute_instance_v2.MasterInstance.*.access_ip_v4, count.index)}"
    }
}

data "template_file" "node_inventory" {
    count = "${var.node_cluster_size}"
    template = "$${ip} ip=$${ip}"
    vars {
        ip = "${element(openstack_compute_instance_v2.NodeInstance.*.access_ip_v4, count.index)}"
    }
}

data "template_file" "etcd_inventory" {
    count = "${var.separate_etcd ? var.etcd_cluster_size : 0 }"
    template = "$${ip} ip=$${ip}"
    vars {
        ip = "${element(openstack_compute_instance_v2.EtcdInstance.*.access_ip_v4, count.index)}"
    }
}

data "template_file" "ansible_inventory" {
    template = "${file("inventory.tpl")}"
    vars {
        master_ip = "${join("\n", data.template_file.master_inventory.*.rendered)}" 
        node_ip = "${join("\n", data.template_file.node_inventory.*.rendered)}" 
        etcd_ip = "${var.separate_etcd ? join("\n", data.template_file.etcd_inventory.*.rendered) : join("\n", data.template_file.master_inventory.*.rendered)}" 
        key_path  = "${local_file.private-key.filename}"
    }
}

resource "null_resource" "update_inventory" {
    triggers {
        template = "${data.template_file.ansible_inventory.rendered}"
    }
    provisioner "local-exec" {
        command = "echo '${data.template_file.ansible_inventory.rendered}' > inventory"
    }
}

