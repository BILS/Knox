How to boot µ-Mosler
====================

The `micromosler` tenant is already set up (on VLAN 20). We have
booked the following floating IPs <code
class=special>130.238.55.4[4-6]</code>. It contains 2 flavors:

* `Default` with id:6 ram:2048 disk:10G and 1 core
* and `ComputeNode` with id:7 ram:8192 disk:20G and 4 cores.

We opted for a plain bash script to boot the micromosler VMs on
Knox. Each VM has 2 network cards and their are booted using the <code
class=special>--user-data</code> flag of the `nova` command:

It uses <code class=special>cloud-init</code> to configure the VMs at
boot time.  It creates the files to configure the static networks, so
that we can reboot the VMs and still have proper network. We use
policy routing so that we can attach a floating IP to either network
without problems. For convenience, we add a `/etc/hosts`
file. Finally, we make sure the ssh-key is added to the `root`
account, and not the `centos` account.

~~~~{.bash}
source /root/openstack/projects/micromosler.rc
source /root/openstack/users/<user>.rc

TENANT=$(openstack project list | awk '/micromosler/{print $2}')
NET=$(neutron net-list --tenant_id=$TENANT | awk '/micromosler/{print $2}')

cat > vm_init-<number>.yml <<ENDNET
#cloud-config
debug: 1
disable_root: 0
password: hello
chpasswd: { expire : False }
ssh_pwauth: True
system_info:
  default_user:
    name: root

bootcmd:
  - echo 200 thinlink >> /etc/iproute2/rt_tables

write_files:
  - path: /etc/sysconfig/network-scripts/ifcfg-eth0
    owner: root:root
    permissions: '0644'
    content: |
      TYPE=Ethernet
      BOOTPROTO=static
      DEFROUTE=yes
      NAME=eth0
      DEVICE=eth0
      ONBOOT=yes
      IPADDR=192.168.20.<number>
      PREFIX=24
      GATEWAY=192.168.20.1
      NM_CONTROLLED=no

  - path: /etc/sysconfig/network-scripts/ifcfg-eth1
    owner: root:root
    permissions: '0644'
    content: |
      TYPE=Ethernet
      BOOTPROTO=static
      DEFROUTE=no
      NAME=eth1
      DEVICE=eth1
      ONBOOT=yes
      IPADDR=192.168.21.<number>
      PREFIX=24
      #GATEWAY=192.168.21.1
      NM_CONTROLLED=no

  - path: /etc/sysconfig/network-scripts/rule-eth1
    owner: root:root
    permissions: '0644'
    content: |
      to 192.168.21.0/24 lookup thinlink
      from 192.168.21.0/24 lookup thinlink

  - path: /etc/sysconfig/network-scripts/route-eth1
    owner: root:root
    permissions: '0644'
    content: |
      default via 192.168.21.1 dev eth1 table thinlink

  - path: /etc/hosts
    owner: root:root
    permissions: '0644'
    content: |
      127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
      ::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
      # Management network is 192.168.20.0/24
      192.168.20.10  firewall
      192.168.20.11  login-node
      192.168.20.12  bastion
      192.168.20.13  filsluss
      192.168.20.14  thinlink-master
      192.168.20.15  storage
      192.168.20.16  auth-services
      192.168.20.17  openstack-controller
      192.168.20.18  horizon
      192.168.20.19  web-relay
      192.168.20.101 compute-node-1
      192.168.20.102 compute-node-2
      192.168.20.103 compute-node-3
      # Thinlink network is 192.168.21.0/24

runcmd:
  - echo 'Restarting network'
  - systemctl restart network 
ENDNET

# Booting a machine
nova boot \
--flavor "<flavor>" \
--image 'CentOS7-micromosler' \
--nic net-id=$NET,v4-fixed-ip=192.168.20.<number> \
--nic net-id=$NET,v4-fixed-ip=192.168.21.<number> \
--key-name "<ssh-key-pair>" \
--security-groups 'default,micromosler-rules' \
--user-data vm_init-<number>.yml \
"<name>"
~~~~

Unfortunately, the file injection using the `--file` flag did not seem
to work. That would have been a slightly simpler and shorter
`#cloud-config` section.

> We initially prepared another image, `CentOS7-micromosler`, with
> updated packages and kernels, where we removed the `centos` user and
> added some ssh-keys to the root account.

In order to log onto the machines, we can log onto the
[dashboard](http://knox.bils.se), and associate one of the floating
IPs. For convenience, it is maybe advised to add to `~/.ssh/config`

~~~~
Host 130.238.55.44 130.238.55.45 130.238.55.46
     User root
     StrictHostKeyChecking no
     UserKnownHostsFile=/dev/null
     IdentityFile ~/.ssh/<my-micromosler-ssh-key>
~~~~


