#!/bin/bash
# SPDX-License-Identifier: GPL-2.0

# This test uses standard topology for testing gretap. See
# ../../../net/forwarding/mirror_gre_topo_lib.sh for more details.
#
# Test offloading various features of offloading gretap mirrors specific to
# mlxsw.

lib_dir=$(dirname $0)/../../../net/forwarding

NUM_NETIFS=6
source $lib_dir/lib.sh
source $lib_dir/mirror_lib.sh
source $lib_dir/mirror_gre_lib.sh
source $lib_dir/mirror_gre_topo_lib.sh

ALL_TESTS="
	test_keyful
	test_soft
	test_tos_fixed
	test_ttl_inherit
"

setup_keyful()
{
	tunnel_create gt6-key ip6gretap 2001:db8:3::1 2001:db8:3::2 \
		      ttl 100 tos inherit allow-localremote \
		      key 1234

	tunnel_create h3-gt6-key ip6gretap 2001:db8:3::2 2001:db8:3::1 \
		      key 1234
	ip link set h3-gt6-key vrf v$h3
	matchall_sink_create h3-gt6-key

	ip address add dev $swp3 2001:db8:3::1/64
	ip address add dev $h3 2001:db8:3::2/64
}

cleanup_keyful()
{
	ip address del dev $h3 2001:db8:3::2/64
	ip address del dev $swp3 2001:db8:3::1/64

	tunnel_destroy h3-gt6-key
	tunnel_destroy gt6-key
}

setup_soft()
{
	# Set up a topology for testing underlay routes that point at an
	# unsupported soft device.

	tunnel_create gt6-soft ip6gretap 2001:db8:4::1 2001:db8:4::2 \
		      ttl 100 tos inherit allow-localremote

	tunnel_create h3-gt6-soft ip6gretap 2001:db8:4::2 2001:db8:4::1
	ip link set h3-gt6-soft vrf v$h3
	matchall_sink_create h3-gt6-soft

	ip link add name v1 type veth peer name v2
	ip link set dev v1 up
	ip address add dev v1 2001:db8:4::1/64

	ip link set dev v2 vrf v$h3
	ip link set dev v2 up
	ip address add dev v2 2001:db8:4::2/64
}

cleanup_soft()
{
	ip link del dev v1

	tunnel_destroy h3-gt6-soft
	tunnel_destroy gt6-soft
}

setup_prepare()
{
	h1=${NETIFS[p1]}
	swp1=${NETIFS[p2]}

	swp2=${NETIFS[p3]}
	h2=${NETIFS[p4]}

	swp3=${NETIFS[p5]}
	h3=${NETIFS[p6]}

	vrf_prepare
	mirror_gre_topo_create

	ip address add dev $swp3 2001:db8:2::1/64
	ip address add dev $h3 2001:db8:2::2/64

	ip address add dev $swp3 192.0.2.129/28
	ip address add dev $h3 192.0.2.130/28

	setup_keyful
	setup_soft
}

cleanup()
{
	pre_cleanup

	cleanup_soft
	cleanup_keyful

	ip address del dev $h3 2001:db8:2::2/64
	ip address del dev $swp3 2001:db8:2::1/64

	ip address del dev $h3 192.0.2.130/28
	ip address del dev $swp3 192.0.2.129/28

	mirror_gre_topo_destroy
	vrf_cleanup
}

test_span_gre_ttl_inherit()
{
	local tundev=$1; shift
	local type=$1; shift
	local what=$1; shift

	RET=0

	ip link set dev $tundev type $type ttl inherit
	mirror_install $swp1 ingress $tundev "matchall"
	fail_test_span_gre_dir $tundev

	ip link set dev $tundev type $type ttl 100

	quick_test_span_gre_dir $tundev
	mirror_uninstall $swp1 ingress

	log_test "$what: no offload on TTL of inherit"
}

test_span_gre_tos_fixed()
{
	local tundev=$1; shift
	local type=$1; shift
	local what=$1; shift

	RET=0

	ip link set dev $tundev type $type tos 0x10
	mirror_install $swp1 ingress $tundev "matchall"
	fail_test_span_gre_dir $tundev

	ip link set dev $tundev type $type tos inherit
	quick_test_span_gre_dir $tundev
	mirror_uninstall $swp1 ingress

	log_test "$what: no offload on a fixed TOS"
}

test_span_failable()
{
	local tundev=$1; shift
	local what=$1; shift

	RET=0

	mirror_install $swp1 ingress $tundev "matchall"
	fail_test_span_gre_dir  $tundev
	mirror_uninstall $swp1 ingress

	log_test "fail $what"
}

test_keyful()
{
	test_span_failable gt6-key "mirror to keyful gretap"
}

test_soft()
{
	test_span_failable gt6-soft "mirror to gretap w/ soft underlay"
}

test_tos_fixed()
{
	test_span_gre_tos_fixed gt4 gretap "mirror to gretap"
	test_span_gre_tos_fixed gt6 ip6gretap "mirror to ip6gretap"
}


test_ttl_inherit()
{
	test_span_gre_ttl_inherit gt4 gretap "mirror to gretap"
	test_span_gre_ttl_inherit gt6 ip6gretap "mirror to ip6gretap"
}

trap cleanup EXIT

setup_prepare
setup_wait

tests_run

exit $EXIT_STATUS
