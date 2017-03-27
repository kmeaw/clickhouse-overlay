# Copyright 1999-2016 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $

EAPI=6

inherit cmake-utils user check-reqs versionator

DESCRIPTION="An OSS column-oriented database management system for real-time data analysis"
HOMEPAGE="https://clickhouse.yandex"
LICENSE="Apache-2.0"
MY_PN="ClickHouse"
if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/yandex/${MY_PN}.git"
	EGIT_SUBMODULES=( -private )
	SRC_URI=""
	TYPE="unstable"
else
	TYPE="stable"
	SRC_URI="https://github.com/yandex/${MY_PN}/archive/v${PV}-${TYPE}.tar.gz -> ${P}.tar.gz"
	S="${WORKDIR}/${MY_PN}-${PV}-${TYPE}"
fi

SLOT="0/${TYPE}"
IUSE="+server +client mongodb cpu_flags_x86_sse4_2"
KEYWORDS="~amd64"

REQUIRED_USE="
	server? ( cpu_flags_x86_sse4_2 )
"

RDEPEND="dev-libs/libltdl[static-libs]
sys-libs/zlib[static-libs]
dev-libs/libpcre
client? (
	sys-libs/ncurses:0
	sys-libs/readline:0
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
|| ( >=sys-devel/gcc-5.0 >=sys-devel/clang-3.8 )"

pkg_pretend() {
	CHECKREQS_DISK_BUILD="2G"
	# Actually it is 960M on my machine
	check-reqs_pkg_pretend
	if [[ $(tc-getCC) == clang ]]; then
		:
	elif [[ $(gcc-major-version) -lt 5 ]]; then
		eerror "Compilation with gcc older than 6.0 is not supported"
		die "Too old gcc found."
	fi
}

src_prepare() {
	default_src_prepare
	sed -i -r -e "s: -Wno-(for-loop-analysis|unused-local-typedef|unused-private-field): -Wno-unused-variable:g" \
		contrib/libpoco/CMakeLists.txt || die "Cannot patch poco"
	if $(tc-getCC) -no-pie -v 2>&1 | grep -q unrecognized; then
		sed -i -e 's:--no-pie::' -i CMakeLists.txt || die "Cannot patch CMakeLists.txt"
		sed -i -e 's:-no-pie::' -i CMakeLists.txt || die "Cannot patch CMakeLists.txt"
	else
		sed -i -e 's:--no-pie:-no-pie:' -i CMakeLists.txt || die "Cannot patch CMakeLists.txt"
	fi

	sed -i -- "s/VERSION_REVISION .*)/VERSION_REVISION ${PV##*.})/g" libs/libcommon/cmake/version.cmake
	sed -i -- "s/VERSION_DESCRIBE .*)/VERSION_DESCRIBE v${PV}-${TYPE})/g" libs/libcommon/cmake/version.cmake
}

src_configure() {
	DISABLE_MONGODB=1
	use mongodb && DISABLE_MONGODB=0
	export DISABLE_MONGODB
	cmake-utils_src_configure
}

src_compile() {
	cmake-utils_src_compile clickhouse
}

src_install() {
	cd "${BUILD_DIR}"
	einfo $(pwd)
	patchelf --remove-rpath dbms/src/Server/clickhouse

	if use server; then
		exeinto /usr/sbin
		newexe dbms/src/Server/clickhouse clickhouse-server
		newinitd "${FILESDIR}"/clickhouse-server.initd clickhouse

		insinto /etc/clickhouse-server
		doins "${S}"/dbms/src/Server/config.xml
		doins "${S}"/dbms/src/Server/users.xml

		sed -e 's:/opt/clickhouse:/var/lib/clickhouse:g' -i "${ED}/etc/clickhouse-server/config.xml"
		sed -e '/listen_host/s%::<%::1<%' -i "${ED}/etc/clickhouse-server/config.xml"

		dodir /var/lib/clickhouse/data/default /var/lib/clickhouse/metadata/default /var/lib/clickhouse/tmp
		dodir /var/log/clickhouse-server
		fowners -R clickhouse:clickhouse /var/lib/clickhouse
		fperms -R 0750 /var/lib/clickhouse
		fowners -R clickhouse:adm /var/log/clickhouse-server
		fperms -R 0750 /var/log/clickhouse-server
	fi

	if use client; then
		exeinto /usr/bin
		newexe dbms/src/Server/clickhouse clickhouse-client

		insinto /etc/clickhouse-client
		doins "${S}"/dbms/src/Client/config.xml
	fi
}

pkg_setup() {
	if use server; then
		enewgroup clickhouse
		enewuser clickhouse -1 -1 /var/lib/clickhouse clickhouse
	fi
}
