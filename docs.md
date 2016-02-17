Knox
====

This document describes the setup for BILS test environment, called Knox.
It follows the
[following guide](http://docs.openstack.org/liberty/install-guide-rdo/)
with a major twist regarding the [network settings](#Network).

The default tutorial for the newest version of Openstack (at the
moment of writing: Liberty) has been simplified. It is no longer the
case that Neutron is placed on a separate node, and the controller
node has (almost) all the other components of Openstack (Keystone,
Glance, Nova, Cinder, Horizon and the utilities such as the Message
Broker).

Instead, Knox has now one node, called the `controller`, with all the
components, and 3 other compute nodes, called `cn1`, `cn2`, and `cn3`,
with only the compute agent and the network agent.

On every node, the network interfaces `eno1` are used for management
(`10.0.1.0/24`), and `eno2` are used for VM communications
(`10.0.2.0/24`). On the controller, `eno4` is used for connectivity
with the outside world (`130.238.55.40`).

Preliminaries
-------------

On every node, we install the `epel-release` and
`yum-plugin-priorities` packages, and then `chrony` (`ntpd`
replacement), and `centos-release-openstack-liberty`.  We did not
install `openstack-selinux`.

On the `controller`, the message broker is `rabbitmq-server` and the
database backend is `mariadb`. The python bindings should come from
`python2-PyMySQL`, but the package is not available for CentOS. The
fix is to use the old `MySQL-python`, as explained in the following
[bug report](https://bugs.launchpad.net/openstack-manuals/+bug/1501991):

> Upstream uses the PyMySQL library in Liberty, but RDO does not
> provide a package for it. Installations using RDO packages must
> revert to the python-MySQL library for any service that uses an SQL
> database which requires changing the database connection string from
> 'mysql+pymysql://' to 'mysql://'.


The Usual suspects
------------------

<code class="special">Keystone</code>, <code
class="special">Glance</code>, <code class="special">Nova</code> and
<code class="special">Cinder</code> are installed using the
instructions from the
[Openstack Liberty docs](http://docs.openstack.org/liberty/install-guide-rdo/).

The public endpoints use <code
class="special">http://knox.bils.se:`<port>`</code>.

The Firewall, on the `controller`, is <code
class="special">iptables</code>.  We ditched `firewalld`. The relevant
ports must be open in the firewall, so we added a few rules (using the
incoming traffic on `eno4`):

	iptables -N IN_external
	iptables -A INPUT -i eno4 -j IN_external
	iptables -A IN_external -p tcp -m tcp --dport <port> -m conntrack --ctstate NEW -j ACCEPT


<a name=Network />Network
=========================

The first step has nothing to do with Openstack. We want to give
external connectivity to the 3 compute node
<code>cn<sub>_i_</sub></code> through the `controller`, ie <code
class="special">NATing</code>. When the compute nodes don't know where
to send a packet, they send it to their gateway, which has been
configured to be the `controller` (IP address of `eno1` 10.0.1.1). The
default route on each compute node is then

~~~~~~{.bash}
[cn-i] # ip r
default via 10.0.1.1 dev eno1
...
~~~~~~

The Firewall on the `controller` contains a `SNAT` rule that updates
the source IP of any packets to be the controller's IP address.

~~~~~~{.bash}
[controller] # iptables -t nat -A POSTROUTING -o eno4 -j SNAT --to-source 130.238.55.40
~~~~~~

Traffic on the controller needs to be allowed to be forwarded between
`eno1` and `eno4`, so we simplify and allow any traffic that is _not_
incoming on `eno4` to be forwarded.

~~~~~~{.bash}
[controller] # iptables -A FORWARD ! -i eno4 -j ACCEPT
~~~~~~

Moreover, ip forwarding must be enabled, so we add the `sysctl`
setting <code class="special">net.ipv4.ip_forward=1</code>. When the
request comes back, the kernel knows that this connection was
initiated by one of the compute nodes and updates the destination's IP
of the packet accordingly. The compute nodes have internet.

- - - 

On all nodes, we disabled IPv6, so apart from <code
class="special">IPV6INIT=no</code> in the <code
class=special>ifcfg-eno<sub>_i_</sub></code> files, we added the
following `sysctl` settings:

	net.ipv6.conf.all.disable_ipv6=1
	net.ipv6.conf.default.disable_ipv6=1

Moreover, on the compute node, we _do_ want traffic to be filtered on
the bridges. This is how security groups are implemented when the
neutron plugin is Linux Bridges.

	net.bridge.bridge-nf-call-iptables=1
	net.bridge.bridge-nf-call-ip6tables=1

For the compute nodes (only):

~~~~~~{.bash}
[cn-i] # cat > /etc/sysctl.d/02-openstack.conf <<EOF
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.all.rp_filter=0
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
EOF
~~~~~~

See below for the `sysctl` settings of the controller.

Neutron agent in Liberty
------------------------

Neutron is a complex piece of the puzzle to get a functioning
openstack environment. It comes with several plugins (such as
OpenVSwitch, Linux Bridges, VMware NSX, or Cisco virtual switches) to
handle networks or subnets, virtual routers and provides IP
addressing.

Liberty is now using Linux Bridges (and no longer uses OpenVSwitch),
in its installation guide. It is possible that
[OVS is more efficient than Linux Bridges](http://www.opencloudblog.com/?p=66).
However, OVS adds several layers of complexity, and Neutron seems
simpler (to use, to debug) with Linux Bridges.

We explain how we set up Knox using Linux Bridges. If you are only
interested in the working solution currently in place, jump to
[the relevant section](#Solution).

Before Neutron even kicks in, we have the following picture:

~~~~{.sh}
[controller: ~] # ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN 
	inet 127.0.0.1/8 scope host lo
2: eno1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP qlen 1000
	inet 10.0.1.1/24 brd 10.0.1.255 scope global eno1
3: eno2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP qlen 1000
	inet 10.0.2.1/24 brd 10.0.2.255 scope global eno2
4: eno3: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN qlen 1000
5: eno4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP qlen 1000
	inet 130.238.55.40/24 brd 130.238.55.255 scope global eno4
~~~~

and

~~~~{.sh}
[controller: ~] # ip r
default via 130.238.55.1 dev eno4 
10.0.1.0/24 dev eno1  proto kernel  scope link  src 10.0.1.1 
10.0.2.0/24 dev eno2  proto kernel  scope link  src 10.0.2.1 
130.238.55.0/24 dev eno4  proto kernel  scope link  src 130.238.55.40
~~~~

The classic setup, with OVS, was to create beforehand a bridge, say
`br-ex`, and add the interface `eno4` as a port to the bridge. The OVS
plugin would then create the other necessary bridges (`br-int` and
`br-tun`) and connect them with patch ports.  Virtual routers are
implemented as Linux Network namespaces and connected to those
bridges. It looked like that:

![OVS](/img/neutron-initialnetworks.png)

- - -

The Linux Bridges plugin does not require to create the external
bridge. It only requires to specify which interface will be mapped to
the external network that neutron will create. In our case, it is
`eno4`. Moreover, we don't want tunneling on the interfaces
`eno2`. Tunneling is layer 3, which meaning wrapping and unwrapping IP
packets constantly. So it'll be plain VLANs and Linux bridges.

Off we go, we update `physical_interface_mappings = public:eno4` in
the file `/etc/neutron/plugins/ml2/linuxbridge_agent.ini`, we create a
`public` network in neutron, and restart neutron. We loose
connectivity for a while. The Linux Bridges plugin had created a
bridge for the public network with a random name (which starts with
`brq-` and finishes with an UUID). The interface `eno4` was added to
that bridge. The public IP was transfered onto the bridge, the routes
were adjusted (by the plugin), and we got back connectivity.

However, we lost NATing! The other compute nodes do not have internet
anymore. When an interface is added to a bridge, we somehow lose
control over it. The `iptables` SNAT rules were mentioning `eno4`. We
could adjust them using a regular expression, such as `brq+` instead,
but the rules would then apply to any bridges which name starts with
`brq`. That doesn't look good since Neutron creates MANY such
bridges. One for each tenant.

- - -

We also have another specific goal: We don't want to loose public IP
addresses. We want the public network not to be `130.238.55.0/24`
because any virtual router plugged onto that network would steal one
of these IP addresses, and we'd loose that IP for no good reason. We
only have a few IP adresses (`130.238.55.[40-49]`). Therefore, we are
going to create two address pools: the previous one for floating IPs
(`130.238.55.[41-49]`) and another one, called "local"
(`10.1.0.0/16`), for the virtual routers. The neutron command line in
Liberty allows us to select from which pool we pick when we create a
virtual router. For example (omitting the DNS settings):

~~~~{.bash}
source admin.rc

# Public Net
neutron net-create --router:external --provider:physical_network public --provider:network_type flat public

# Public Subnet - For floating IPs
neutron subnet-create --name public-subnet \
--allocation-pool start=130.238.55.41,end=130.238.55.49 --disable-dhcp --gateway 130.238.55.1 \
public 130.238.55.0/24

# Local Subnet 
neutron subnet-create --name local-subnet \
--allocation-pool start=10.1.0.2,end=10.1.0.150 --disable-dhcp --gateway 10.1.0.1 \
public 10.1.0.0/16
~~~~

And as the tenant "Knox":

~~~~{.bash}
source knox.rc
# VLAN 10 for Knox
neutron net-create --provider:network_type vlan --provider:physical_network vlan \
--provider:segmentation_id 10 knox-net
# Create a virtual router
neutron router-create knox-router
# Pick an address from 10.1.0.0/16
neutron router-gateway-set --fixed-ip subnet_id=local-subnet knox-router public
# Creates a dhcp namespace
neutron subnet-create --name knox-subnet --gateway 192.168.10.1 --enable-dhcp knox-net 192.168.10.0/24
# Connect the router to the private subnet
neutron router-interface-add knox-router knox-subnet
~~~~

- - -

A solution would be to create a bridge, before-hand, say `br-ex`
(surprise!), and a `veth` pair, say <code class="special">tap4 <->
veno4</code>. Both `eno4` and `tap4` are added as ports onto `br-ex`,
and `veno4` is the new setting to be added to neutron. The Linux
Bridges plugin would not touch `eno4`, nor `br-ex`, but it would play
with `veno4`. The `SNAT` rule can now be updated and use `br-ex`.

![br-ex first idea](/img/br-ex-1.jpeg)

After Neutron kicks in, it steals the interface, removes the routes
related to `veno4` if there were any (remember that for later), and adds
the IP for the public network to the bridge. For simplicity, in the
pictures, we named the bridge `brq-public`. In reality, it looks like
`brq16eb8e8c-f2`. Neutron goes on creating the virtual router for the
tenants (here, only one), and we end up with the following (partial)
figure:

![br-ex first idea (2)](/img/br-ex-2.jpeg)

`qg` is the router gateway. In reality, it is the end of a `veth`
pair, with a name like `qg-<uuid>`, and the other end is added to the
bridge `brq-public` in the root namespace.

Neutron creates also a DHCP server inside a dedicated namespace. In
the example, the tenant we create is on VLAN 10, with a private subnet
`192.168.10.0/24`. The complete picture is:

![br-ex first idea (3)](/img/br-ex-3.jpeg)

However, <code class=special>this does not work</code>. ARP requests
don't reach the Virtual Router namespace, but they do sometimes if the
IP in the public bridge is removed and added back as it was, by
hand. We can see traffic flowing one way between `tap4` and `veno4`,
but not the other way. Or traffic going to one port of a bridge but
not the other port! That is strange, and not a sustainable solution.

Secondly, if we log onto the virtual router (using `ip netns exec
qrouter-<uuid> bash`), we can then issue commands like `ping 8.8.8.8`
(google).  We wanted the network inside the router to be "local". So
the source IP of each ICMP packet is the address of the router
interface `qr-<uuid>` (Here in the examples `10.1.0.2`). Since a
packet originating from the router namespace reaches the root
namespace through the bridge `brq-public`, the packet is filtered
through `iptables`, which has no matching rules. The packet will _not_
be refiltered, so when it makes its way to `eno4`, its source IP has
not been SNATed. Therefore, it goes out to the real world as coming
from `10.1.0.2` and never comes back.

If the router was luckily setup with a public IP (say,
`130.238.55.41`, instead of `10.1.0.2`), the packet would then come
back (as `130.238.55.41` and not `130.238.55.40` if NATing had not
failed). That only would work if the ARP requests for 138.238.55.41 do
reach the router namespace, which is the case if we turn on STP on the
bridge `br-ex`. We then avoid that the requests be bouncing around.

Assume now that we temporarily adjust the iptables rule so that packet
coming onto `brq-public` are also filtered and SNATed. We would then
suffer from another problem: ICMP redirects. When we `ping 8.8.8.8`
from the router, according to its route tables, the router will send
the packets to its gateway, which is `10.1.0.1`. The role of the
bridge is to copy the packets to all its ports. The packets will
somehow come back before it goes out to the internet. This is better
explained
[here](http://www.cymru.com/gillsr/documents/icmp-redirects-are-bad.htm).

All in all, that does not look good. We need something else!

<a name=Solution />The solution
-------------------------------

The solution deals with the policy routing.

We would like the virtual router namespace to behave the same way,
regarding NATing, as the compute nodes. From the compute nodes, a
packet for the outside world arrives on `eno1` and the kernel inspects
its routing table. It has to send the packet to the controller's
gateway (the outside machine `130.238.55.1`), and therefore, forwards
the packet from `eno1` to `eno4`, which is then SNATed by the
firewall. The kernel will remember the connection when the request
comes back and send it appropriately to the compute nodes, after
inspecting again its routing tables.

First, when an ARP request is snooped by `eno4` (the only entrance to
Knox), we must make that particular interface answer the ARP requests
on behalf of the other interfaces inside the virtual routers that have
floating IP adresses.  This is done with a `sysctl` setting: We turn
on `proxy_arp` for `eno4`.

	net.ipv4.conf.eno4.proxy_arp=1

We now go on creating the interface for the virtual routers that plays
the same role as `eno1` does for the compute nodes. Everything is
virtual in Neutron, so we might as well create a `tap` interface (that
will only exist in the kernel). We call it `veno4` and allow traffic
to be forwarded between `eno4` and `veno4`. No need to use the "free"
`eno3`.

~~~~{.bash}
iptables -A FORWARD -i eno4 -o veno4 -j ACCEPT
~~~~

In the file `/etc/iproute2/rt_tables`, we append the line <code
class=special>10 openstack</code>, so that the table is added at
booting time. Then we add a rule that says that the routing
information for `130.238.55.0/24` should be looked up in table
`openstack`. Finally, we add a few routes, of the form <code
class=special>130.238.55.4<i>i</i> via 10.1.0.1</code> to that table
(where _i_ is in {1..9}). We don't need to specify the device, the
clause `via 10.1.0.1` does the trick.

~~~~{.bash}
cat > /etc/sysconfig/network-scripts/rule-veno4 <<EOF
to 130.238.55.0/24 lookup openstack
EOF

cat > /etc/sysconfig/network-scripts/route-veno4 <<EOF
# Adding the routes for the floating IPs
130.238.55.41 via 10.1.0.1 table openstack
130.238.55.42 via 10.1.0.1 table openstack
130.238.55.43 via 10.1.0.1 table openstack
130.238.55.44 via 10.1.0.1 table openstack
130.238.55.45 via 10.1.0.1 table openstack
130.238.55.46 via 10.1.0.1 table openstack
130.238.55.47 via 10.1.0.1 table openstack
130.238.55.48 via 10.1.0.1 table openstack
130.238.55.49 via 10.1.0.1 table openstack
EOF
~~~~

Note that `130.238.55.40` is not added, so the kernel will default
back to the next route, looking up its `main` table. If we check the
route to `130.238.55.41`, we get:

~~~~{.bash}
[controller: ~] # ip route get 130.238.55.41
130.238.55.41 dev veno4  src 10.1.0.1 
~~~~

Finally, not that the `10.1.0.0/16` traffic is routed of course
through `veno4`.

~~~~{.sh hl_lines="5"}
[controller: ~] # ip r
default via 130.238.55.1 dev eno4 
10.0.1.0/24 dev eno1  proto kernel  scope link  src 10.0.1.1 
10.0.2.0/24 dev eno2  proto kernel  scope link  src 10.0.2.1 
10.1.0.0/16 dev veno4  proto kernel  scope link  src 10.1.0.1 
130.238.55.0/24 dev eno4  proto kernel  scope link  src 130.238.55.40
~~~~

However, we are facing another problem: When Neutron kicks in, it
takes the interface `veno4` and adds it as a port to the public
bridge. It also adjusts the IP address of the bridge, but this erases
the routes! We can log onto knox, but none of the floating IPs does
answer. We want a solution that is persistent across a reboot!

So we have the following idea: we use another `veth` pair! We'll give
Neutron one end, that does not have any IP and is not mentioned in any
routing rules. The other end, though, does. We call the pair <code
class=special>veno4 <-> osext</code>. `osext` is given as bridge
mapping in the linux bridges configuration file.

We also create the following custom-made `ifcfg-veno4` file, along
with the associated `ifup` and `ifdown` scripts. Don't forget to
`chmod +x` the scripts, or the network service will revert back to
using `ifup-eth` and choke!

~~~~{.bash hl_lines="6 7 8"}
NAME=veno4
DEVICE=veno4
IPADDR=10.1.0.1
PREFIX=16
ONBOOT=yes
TYPE=veth
DEVICETYPE=veth
PATCH=osext
~~~~

The script `ifup-veth` simply creates the `veth` pair, and adds the IP
address to one end. The last step is to call the script that sets up
the routes (using veno4).

~~~~{.bash}
!/bin/bash

# Author: Frédéric Haziza
#   Date: December 2015

. /etc/init.d/functions

cd /etc/sysconfig/network-scripts
. ./network-functions

[ -f ../network ] && . ../network

CONFIG=${1}

need_config ${CONFIG}

source_config

# Creating a veth pair so that Openstack adds on side to its
# external bridge, but doesn't flush the IP and routes
# (since they'll be on the other side of the pair)
/sbin/ip -4 link add ${PATCH} type ${TYPE} peer name ${NAME}

/sbin/ip -4 link set dev ${PATCH} promisc on
/sbin/ip -4 link set dev ${NAME} promisc on

/sbin/ip -4 addr add ${IPADDR}/${PREFIX} dev ${NAME}

/sbin/ip -4 link set dev ${PATCH} up
/sbin/ip -4 link set dev ${NAME} up

# Taking care of the routes
exec /etc/sysconfig/network-scripts/ifup-post ${CONFIG} ${2}
~~~~

It is not hard to derive the `ifdown-veth` file from `ifdown-eth`.
Deleting any end of a `veth` pair deletes both ends.

	/sbin/ip link delete ${PATCH} type ${TYPE}

We do _not_ want traffic to be filtered by the bridges (on the
controller node), since we'll have the same NATing problem as
above. We turn it off with some `sysctl` settings.

In the file `/etc/sysctl.d/02-openstack-neutron.conf`

~~~~
net.ipv4.ip_forward=1
#
# Don't let the bridged traffic be filtered
net.bridge.bridge-nf-call-iptables=0
...
#
# Disable IPv6
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
#
# Making eno4 answer ARP on behalf of veno4
net.ipv4.conf.eno4.proxy_arp=1
~~~~

Finally, the setup looks like that:

![Final setup](/img/final-setup.jpeg)

Of course, the switch sitting in between the nodes must be configured
to allow VLAN 10 (or any other VLAN used by Neutron) on the ports
connected to the `eno2` interfaces of the compute nodes.

Notes
-----

The package `iproute2` has been upgraded and is not yet compatible
with Neutron.  The issue has to do with a
[parsing problem](https://bugs.launchpad.net/neutron/+bug/1528977),
such that Neutron tries to create the router namespace, fails, and
then doesn't go on to create the necessary interfaces and connections
from the router namespace to the bridges in the root
namespace. Therefore, nothing works. The VMs can be booted, but they
have no connectivity.

A solution is to revert to an older version of `iproute2`, but we
prefered to
[patch the neutron code](https://review.openstack.org/#/c/258493/1/neutron/agent/linux/ip_lib.py). This
will probably be fixed in the coming days.

- - - 
Frédéric Haziza <daz@bils.se>, December 2015.
