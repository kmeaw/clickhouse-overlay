# Copyright 1999-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $

EAPI=6

inherit cmake-utils user check-reqs versionator git-r3

DESCRIPTION="An open-source column-oriented database management system that allows generating analytical data reports in real time"
MY_PN="ClickHouse"
MY_PV="$(get_version_component_range 3)"
# SRC_URI="https://github.com/yandex/${MY_PN}/archive/${MY_PV}.tar.gz -> ${MY_PN}-r${MY_PV}.tar.gz"
SRC_URI=""
EGIT_REPO_URI="https://github.com/yandex/${MY_PN}.git"
EGIT_SUBMODULES=( -private )

if [[ ${PV} != 9999 ]]; then
	EGIT_COMMIT=${MY_PV}
fi

SLOT="0"
IUSE="+server +client mongodb"
KEYWORDS="~amd64"

RDEPEND="dev-libs/libltdl[static-libs]
sys-libs/zlib[static-libs]
dev-libs/libpcre
client? (
	sys-libs/ncurses
	sys-libs/readline
)
|| (
	dev-db/unixODBC[static-libs]
	dev-libs/poco[odbc]
)"

DEPEND="${RDEPEND}
sys-libs/libtermcap-compat[static-libs]
dev-libs/icu[static-libs]
dev-libs/glib[static-libs]
dev-libs/boost[static-libs]
dev-libs/openssl[static-libs]
dev-libs/zookeeper-c[static-libs]
dev-util/patchelf
virtual/libmysqlclient[static-libs]
>=sys-devel/gcc-5"

pkg_pretend() {
	CHECKREQS_DISK_BUILD="18G"
	check-reqs_pkg_pretend
	if use server; then
		grep -q sse4_2 /proc/cpuinfo || \
			ewarn "SSE 4.2 is not supported, server would not work on this machine"
	fi
}

src_unpack() {
	git-r3_src_unpack
}

src_prepare() {
	default_src_prepare
	sed -i -r -e "s: -Wno-(for-loop-analysis|unused-local-typedef|unused-private-field): -Wno-unused-variable:g" \
		contrib/libpoco/CMakeLists.txt || die "Cann-t patch poco"
}

src_configure() {
	DISABLE_MONGODB=1
	use mongodb && DISABLE_MONGODB=0
	export DISABLE_MONGODB
	cmake-utils_src_configure
}

src_compile() {
	cmake-utils_src_compile $(use server && echo clickhouse-server) $(use client && echo clickhouse-client)
}

src_install() {
	cd "${BUILD_DIR}"
	einfo $(pwd)
	if use server; then
		exeinto /usr/sbin
		patchelf --remove-rpath dbms/src/Server/clickhouse-server
		doexe dbms/src/Server/clickhouse-server
		newinitd "${FILESDIR}"/clickhouse-server.initd clickhouse

		insinto /etc/clickhouse-server
		doins ${S}/dbms/src/Server/config.xml
		doins ${S}/dbms/src/Server/users.xml

		sed -e 's:/opt/clickhouse:/var/lib/clickhouse:g' -i "${ED}/etc/clickhouse-server/config.xml"

		dodir /var/lib/clickhouse/data/default /var/lib/clickhouse/metadata/default /var/lib/clickhouse/tmp
		dodir /var/log/clickhouse-server
		fowners -R clickhouse:clickhouse /var/lib/clickhouse
		fperms -R 0750 /var/lib/clickhouse
		fowners -R clickhouse:adm /var/log/clickhouse-server
		fperms -R 0750 /var/log/clickhouse-server
	fi

	if use client; then
		exeinto /usr/bin
		patchelf --remove-rpath dbms/src/Client/clickhouse-client
		doexe dbms/src/Client/clickhouse-client

		insinto /etc/clickhouse-client
		doins ${S}/dbms/src/Client/config.xml
	fi
}

pkg_setup() {
	if use server; then
		enewgroup clickhouse
		enewuser clickhouse -1 -1 /var/lib/clickhouse clickhouse

	fi
}
