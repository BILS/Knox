How to Use Knox
===============

Knox is an [Openstack](http://www.openstack.org) environment, and as
such, it boots virtual machines to be used within
[BILS](http://www.bils.se).

This document describes how to use Knox environment. Check out the
following guide to know more about [how Knox is set up](./docs.html).

There are 2 roles in Knox: the `admin` role, for administrative
purposes, and the `member` role, for all other operations.

For each project within Knox, we want to use a separate `tenant`. A
tenant can configure routers, networks, rules and virtual machines
(VMs) that are disconnected from those of another tenant.

In particular, there is already a special tenant, called also <code
class="special">knox</code>, to be used if we don't want to configure
everything and only want to quickly boot up a VM.  One tenant per
project is a convenient way to secure access to virtual machines
between the different projects. Internally, we attribute a separate
VLAN for each tenant. Currently:

* the tenant <code class="special">knox</code> is on VLAN 10,
* the tenant <code class="special">micromosler</code> is on VLAN 20
* and VLAN 30 and 40 are available.

We can, of course, use any VLAN, but VLAN 10, 20, 30 and 40 are
already configured in the physical switch for the ports that are
connected to the compute nodes. Let us know if you have a favorite
number ;-).

We have booked the following floating IPs for the `knox` tenant: <code
class=special>130.238.55.4[1-3]</code>. `130.238.55.4[4-6]` are used
for `micromosler`, and `130.238.55.4[7-9]` are still available.

If someone only wants a quick setup in the cloud, and use a machine
for some tests, it is simpler to use the `knox` tenant, as it is
already configured. On the other hand, if we have the needs for a
particular, we can then contact an administrator to set it up. The
reason is that a tenant which needs a particular network will be
attributed some random VLAN (or the one specified at creation), and
that this VLAN must be configured in the physical switch.

In order for an administrator to issue any command, she needs to
source the tenant's `.rc` file, along with the user's `.rc` file. I
placed the tenant files under `/root/openstack/projects` and the users
credentials in `/root/openstack/users`. For example, I can issue
commands for the knox tenant if I sourced
`/root/openstack/projects/knox.rc` and `/root/openstack/users/daz.rc`
(and yes, you can read the passwords if you have root access on Knox).

>Note that we do _not_ use the `admin` tenant! We prefer to give a
>particular user the admin role for some tenant, than adding that user
>to the `admin` tenant. The only ones who can use the `admin` tenant
>are the ones with root access on knox.

How to configure a tenant
=========================

We illustrate how to create the components within a tenant. This is
how the `knox` tenant is set up. It contains a router connected on one
side to the already configured external network, and on the other
side, to a newly created network (on VLAN 10).

Internally, an administrator can create the components with the following commands:
~~~~{.bash hl_lines="15"}
# Use your credentials for Knox
source /root/openstack/projects/<tenant>.rc
source /root/openstack/users/<user>.rc

# Create the network on VLAN 10
neutron net-create \
--provider:network_type vlan \
--provider:physical_network vlan \
--provider:segmentation_id <chosen_vlan> \
<net_name>

# Create the router
neutron router-create <router_name>
# Attach to external network, called public, using the local-subnet IP range
neutron router-gateway-set --fixed-ip subnet_id=local-subnet <router_name> public

# Create the local IP range for that tenant (Here: 192.168.10.0/24)
neutron subnet-create --name <subnet_name> --gateway 192.168.10.1 --enable-dhcp \
--dns-nameserver 130.238.7.10 --dns-nameserver 130.238.4.11 --dns-nameserver 130.238.164.6 \
<net_name> 192.168.10.0/24

# Attach the router to that network
neutron router-interface-add <router_name> <subnet_name>
~~~~

Using the dashboard, the previous operations are somewhat more
limited, and you can't specify the VLAN. Moreover, attaching the
router to the external network using the `public-subnet` would steal a
public address. It needs to use the `local-subnet` (as on the
highlighted line).


Remote access
=============

Apart from using the [dashboard](http://knox.bils.se), the public
endpoints are <code
class="special">http://knox.bils.se:`<port>`</code>. You can connect
to the different components of Knox, remotely, using the
[Openstack Rest API](http://docs.openstack.org).

| Project       | Port          |
| ------------- | -------------:|
| Keystone      | 5000          |
| Nova          | 8774          |
| Neutron       | 9696          |
| Cinder        | 9292          |

We first get a token from Keystone for identification by hitting
`http://knox.bils.se:5000/v2.0/tokens` (granted that we identify
ourselves with project, username and password). We then can request
information, using that token, from the different services, like Nova
or Neutron.

For example, `http://knox.bils.se:8774/v2.1/​<tenant_id>​/servers` would
list all the VMs under a particular tenant, or
`http://knox.bils.se:9696/v2.0/networks/<network_id>` to show the
details of a particular network.


Vagrant example
---------------

Shall I write an example, and explain why we moved on to using plain bash script?

![Final setup](/img/final-setup.jpeg)


- - - 
Frédéric Haziza <daz@bils.se>, January 2016.
