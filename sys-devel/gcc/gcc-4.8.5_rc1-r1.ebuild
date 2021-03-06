# Distributed under the terms of the GNU General Public License v2

# See README.txt for usage notes.

EAPI=5

inherit multilib eutils pax-utils

RESTRICT="strip"
FEATURES=${FEATURES/multilib-strict/}

IUSE="go +fortran objc objc++ openmp" # languages
IUSE="$IUSE cxx nls vanilla doc multilib altivec libssp hardened" # other stuff
IUSE="$IUSE fpu_vfp fpu_vfpv3 fpu_vfpv3-fp16 fpu_vfpv3-d16 fpu_vfpv3-d16-fp16 fpu_vfpv3xd \
		fpu_vfpv3xd-fp16 fpu_neon fpu_neon-fp16 fpu_vfpv4 fpu_vfpv4-d16 fpu_fpv4-sp-d16 \
		fpu_neon-vfpv4 fpu_fpv5-d16 fpu_fpv5-sp-d16 fpu_fp-armv8 fpu_neon-fp-armv8 \
		fpu_crypto-neon-fp-armv8" # user-selectable fpu options for cross-compile 
		# ref: https://gcc.gnu.org/onlinedocs/gcc-6.2.0/gcc/ARM-Options.html
SLOT="${PV}"

#Hardened Support:
#
# PIE_VER specifies the version of the PIE patches that will be downloaded and applied.
#
# SPECS_VER and SPECS_GCC_VER specifies the version of the "minispecs" files that will
# be used. Minispecs are compiler definitions that are installed that can be used to
# select various permutations of the hardened compiler, as well as a non-hardened
# compiler, and are typically selected via Gentoo's gcc-config tool.
PIE_VER="0.6.2"
SPECS_VER="0.2.0"
SPECS_GCC_VER="4.4.3"
SPECS_A="gcc-${SPECS_GCC_VER}-specs-${SPECS_VER}.tar.bz2"
PIE_A="gcc-${PV}-piepatches-v${PIE_VER}.tar.bz2"

GMP_VER="5.1.2"
MPFR_VER="3.1.2"
MPC_VER="1.0.1"

# GENTOO_PATCH_VER specifies the version of Gentoo's patches being applied to this
# gcc version.
GENTOO_PATCH_VER="1.3"
GENTOO_PATCH_VER_A="gcc-${PV}-patches-${GENTOO_PATCH_VER}.tar.bz2"

GCC_A="gcc-${PV}.tar.bz2"
SRC_URI="mirror://gnu/gcc/gcc-${PV}/${GCC_A}"
SRC_URI="$SRC_URI mirror://funtoo/gcc/${GENTOO_PATCH_VER_A}"
SRC_URI="$SRC_URI http://www.multiprecision.org/mpc/download/mpc-${MPC_VER}.tar.gz"
SRC_URI="$SRC_URI http://www.mpfr.org/mpfr-${MPFR_VER}/mpfr-${MPFR_VER}.tar.xz"
SRC_URI="$SRC_URI mirror://gnu/gmp/gmp-${GMP_VER}.tar.xz"

#Hardened Support:
SRC_URI="$SRC_URI hardened? ( mirror://funtoo/gcc/${SPECS_A} mirror://funtoo/gcc/${PIE_A} )"

DESCRIPTION="The GNU Compiler Collection"

LICENSE="GPL-3+ LGPL-3+ || ( GPL-3+ libgcc libstdc++ gcc-runtime-library-exception-3.1 ) FDL-1.3+"
KEYWORDS="*"

RDEPEND="sys-libs/zlib nls? ( sys-devel/gettext ) virtual/libiconv !sys-devel/gcc:4.8"
DEPEND="${RDEPEND} >=sys-devel/bison-1.875 >=sys-devel/flex-2.5.4 elibc_glibc? ( >=sys-libs/glibc-2.8 ) >=sys-devel/binutils-2.18"
PDEPEND=">=sys-devel/gcc-config-1.5 >=sys-devel/libtool-2.4.3 elibc_glibc? ( >=sys-libs/glibc-2.8 )"

tc-is-cross-compiler() {
	[[ ${CBUILD:-${CHOST}} != ${CHOST} ]]
}

is_crosscompile() {
	[[ ${CHOST} != ${CTARGET} ]]
}

pkg_setup() {
	unset GCC_SPECS # we don't want to use the installed compiler's specs to build gcc!
	unset LANGUAGES #265283
	PREFIX=/usr
	CTARGET=${CTARGET:-${CHOST}}
	[[ ${CATEGORY} == cross-* ]] && CTARGET=${CATEGORY/cross-}
	GCC_BRANCH_VER=${SLOT}
	GCC_CONFIG_VER=${PV}
	DATAPATH=${PREFIX}/share/gcc-data/${CTARGET}/${GCC_CONFIG_VER}
	CFLAGS="-O2 -pipe"
	FFLAGS="$CFLAGS"
	FCFLAGS="$CFLAGS"
	CXXFLAGS="$CFLAGS"
	if is_crosscompile; then
		BINPATH=${PREFIX}/${CHOST}/${CTARGET}/gcc-bin/${GCC_CONFIG_VER}
	else
		BINPATH=${PREFIX}/${CTARGET}/gcc-bin/${GCC_CONFIG_VER}
	fi
	LIBPATH=${PREFIX}/lib/gcc/${CTARGET}/${GCC_CONFIG_VER}
	STDCXX_INCDIR=${LIBPATH}/include/g++-v${GCC_BRANCH_VER}
}

src_unpack() {
	unpack $GCC_A
	unpack $GENTOO_PATCH_VER_A

	( unpack mpc-${MPC_VER}.tar.gz && mv ${WORKDIR}/mpc-${MPC_VER} ${S}/mpc ) || die "mpc setup fail"
	( unpack mpfr-${MPFR_VER}.tar.xz && mv ${WORKDIR}/mpfr-${MPFR_VER} ${S}/mpfr ) || die "mpfr setup fail"
	( unpack gmp-${GMP_VER}.tar.xz && mv ${WORKDIR}/gmp-${GMP_VER} ${S}/gmp ) || die "gmp setup fail"

	if use hardened; then
		unpack $PIE_A || die "pie unpack fail"
		unpack $SPECS_A || die "specs unpack fail"
	fi

	cd $S
	mkdir ${WORKDIR}/objdir
}
p_apply() {
	einfo "Applying ${1##*/}..."
	patch -p1 < $1 > /dev/null || die "Failed applying $1"
}

src_prepare() {
	( use vanilla && use hardened ) \
		&& die "vanilla and hardened USE flags are incompatible. Disable one of them"

	# For some reason, when upgrading gcc, the gcc Makefile will install stuff
	# like crtbegin.o into a subdirectory based on the name of the currently-installed
	# gcc version, rather than *our* gcc version. Manually fix this:

	sed -i -e "s/^version :=.*/version := ${GCC_CONFIG_VER}/" ${S}/libgcc/Makefile.in || die

	if ! use vanilla; then
		# The following patch allows pie/ssp specs to be changed via environment
		# variable, which is needed for gcc-config to allow switching of compilers:
		! is_crosscompile && p_apply "${FILESDIR}"/gcc-spec-env-r1.patch

		# Prevent libffi from being installed
		sed -i -e 's/\(install.*:\) install-.*recursive/\1/' "${S}"/libffi/Makefile.in || die
		sed -i -e 's/\(install-data-am:\).*/\1/' "${S}"/libffi/include/Makefile.in || die

		# We use --enable-version-specific-libs with ./configure. This
		# option is designed to place all our libraries into a sub-directory
		# rather than /usr/lib*.  However, this option, even through 4.8.0,
		# does not work 100% correctly without a small fix for
		# libgcc_s.so. See: http://gcc.gnu.org/bugzilla/show_bug.cgi?id=32415.
		# So, we apply a small patch to get this working:
		p_apply "${FILESDIR}"/gcc-4.6.4-fix-libgcc-s-path-with-vsrl.patch

		for gentoo_patch in $WORKDIR/patch/[0-9][0-9]_{all,${ARCH}}*.patch; do
			[ -e "$gentoo_patch" ] && p_apply "$gentoo_patch"
		done

		# Hardened patches
		if use hardened; then
			local gcc_hard_flags="-DEFAULT_RELRO -DEFAULT_BIND_NOW -DEFAULT_PIE_SSP"

			EPATCH_MULTI_MSG="Applying PIE patches..." \
				epatch "${WORKDIR}"/piepatch/*.patch

			sed -e '/^ALL_CFLAGS/iHARD_CFLAGS = ' \
				-e 's|^ALL_CFLAGS = |ALL_CFLAGS = $(HARD_CFLAGS) |' \
				-i "${S}"/gcc/Makefile.in

			sed -e '/^ALL_CXXFLAGS/iHARD_CFLAGS = ' \
				-e 's|^ALL_CXXFLAGS = |ALL_CXXFLAGS = $(HARD_CFLAGS) |' \
				-i "${S}"/gcc/Makefile.in

			sed -i -e "/^HARD_CFLAGS = /s|=|= ${gcc_hard_flags} |" "${S}"/gcc/Makefile.in || die
		fi
	fi
	if is_crosscompile; then
		# if we don't tell it where to go, libcc1 stuff ends up in ${ROOT}/usr/lib (or rather dies colliding)
		CC1DIR="${WORKDIR}/${P}/libcc1"
		sed -i 's%cc1libdir = .*%cc1libdir = /usr/$(host_noncanonical)/$(target_noncanonical)/lib/$(gcc_version)%' ${CC1DIR}/Makefile.am
		sed -i 's%plugindir = .*%plugindir = /usr/lib/gcc/$(target_noncanonical)/$(gcc_version)/plugin%' ${CC1DIR}/Makefile.am
		sed -i 's%cc1libdir = .*%cc1libdir = /usr/$(host_noncanonical)/$(target_noncanonical)/lib/$(gcc_version)%' ${CC1DIR}/Makefile.in
		sed -i 's%plugindir = .*%plugindir = /usr/lib/gcc/$(target_noncanonical)/$(gcc_version)/plugin%' ${CC1DIR}/Makefile.in
		if [[ ${CTARGET} == avr* ]]; then
			sed -i 's%native_system_header_dir=/usr/include%native_system_header_dir=/include%' ${WORKDIR}/${P}/gcc/config.gcc
		fi
	fi	
}

src_configure() {
	local confgcc
	if is_crosscompile || tc-is-cross-compiler; then
		confgcc+=" --target=${CTARGET}"
	fi
	if is_crosscompile; then
		case ${CTARGET} in
			*-linux)			needed_libc=no-idea;;
			*-dietlibc)			needed_libc=dietlibc;;
			*-elf|*-eabi)		needed_libc=newlib;;
			*-freebsd*)			needed_libc=freebsd-lib;;
			*-gnu*)				needed_libc=glibc;;
			*-klibc)			needed_libc=klibc;;
			*-musl*)			needed_libc=musl;;
			*-uclibc*)			needed_libc=uclibc;;
			avr*)				needed_libc=avr-libc;;			
		esac
		if [[ $CTARGET} == avr* ]]; then
			confgcc+=" --disable-bootstrap --enable-poison-system-directories --disable-__cxa_atexit"
		else
			confgcc+=" --disable-bootstrap --enable-poison-system-directories --enable-__cxa_atexit"
		fi
		if ! has_version ${CATEGORY}/${needed_libc}; then
			# we are building with libc that is not installed:
			confgcc+=" --disable-shared --disable-libatomic --disable-threads --without-headers --disable-libstdcxx"
		elif built_with_use --hidden --missing false ${CATEGORY}/${needed_libc} crosscompile_opts_headers-only; then
			# libc installed, but has USE="crosscompile_opts_headers-only" to only install headers:
			confgcc+=" --disable-shared --disable-libatomic --with-sysroot=${PREFIX}/${CTARGET} --disable-libstdcxx"
		else
			# libc is installed:
			confgcc+=" --with-sysroot=${PREFIX}/${CTARGET} --enable-libstdcxx-time"
		fi
		confgcc+=" --disable-libgomp"
	else
		confgcc+=" $(use_enable openmp libgomp)"
	fi
	[[ -n ${CBUILD} ]] && confgcc+=" --build=${CBUILD}"
	# Determine language support:
	local GCC_LANG="c,c++"
	if use objc; then
		GCC_LANG+=",objc"
		confgcc+=" --enable-objc-gc"
		use objc++ && GCC_LANG+=",obj-c++"
	fi
	use fortran && GCC_LANG+=",fortran" || confgcc+=" --disable-libquadmath"
	use go && GCC_LANG+=",go"
	confgcc+=" $(use_enable openmp libgomp)"
	confgcc+=" --enable-languages=${GCC_LANG} --disable-libgcj"
	confgcc+=" $(use_enable hardened esp)"

	use libssp || export gcc_cv_libc_provides_ssp=yes

	# ARM
	if [[ ${CTARGET} == arm* ]] ; then
		local a arm_arch=${CTARGET%%-*}
		# Remove trailing endian variations first: eb el be bl b l
		for a in e{b,l} {b,l}e b l ; do
			if [[ ${arm_arch} == *${a} ]] ; then
				arm_arch=${arm_arch%${a}}
				break
			fi
		done

		# Convert armv7{a,r,m} to armv7-{a,r,m}
		local arm_arch_without_dash=${arm_arch}
		[[ ${arm_arch} == armv7? ]] && arm_arch=${arm_arch/7/7-}
		# See if this is a valid --with-arch flag
		if (srcdir=${S}/gcc target=${CTARGET} with_arch=${arm_arch};
			. "${srcdir}"/config.gcc) &>/dev/null
		then
			confgcc+=" --with-arch=${arm_arch}"
		fi

		# Enable hardvfp
		local float
		local CTARGET_TMP=${CTARGET:-${CHOST}}
		if [[ ${CTARGET_TMP//_/-} == *-softfloat-* ]] ; then
			float="soft"
		elif [[ ${CTARGET_TMP//_/-} == *-softfp-* ]] ; then
			float="softfp"
		else
			if [[ ${CTARGET} == armv[6-8]* ]]; then # unfortunately, use flags don't work with case conditionals
				if use fpu_vfp; then					confgcc+=" --with-fpu=vfp"
				elif use fpu_vfpv3; then				confgcc+=" --with-fpu=vfpv3"
				elif use fpu_vfpv3-fp16; then			confgcc+=" --with-fpu=vpu-vfpv3-fp16"
				elif use fpu_vfpv3-d16; then			confgcc+=" --with-fpu=vfpv3-d16"
				elif use fpu_vfpv3-d16-fp16; then		confgcc+=" --with-fpu=vfpv3-d16-fp16"
				elif use fpu_vfpv3xd; then				confgcc+=" --with-fpu=vfpv3xd"
				elif use fpu_vfpv3xd-fp16; then			confgcc+=" --with-fpu=vfpv3xd-fp16"
				elif use fpu_neon; then					confgcc+=" --with-fpu=neon"
				elif use fpu_neon-fp16; then			confgcc+=" --with-fpu=neon-fp16"
				elif use fpu_vfpv4; then				confgcc+=" --with-fpu=vfpv4"
				elif use fpu_vfpv4-d16; then			confgcc+=" --with-fpu=vfpv4-d16"
				elif use fpu_fpv4-sp-d16; then			confgcc+=" --with-fpu=fpv4-sp-d16"
				elif use fpu_neon-vfpv4; then			confgcc+=" --with-fpu=neon-vfpv4"
				elif use fpu_fpv5-d16; then				confgcc+=" --with-fpu=fpv5-d16"
				elif use fpu_fpv5-sp-d16; then			confgcc+=" --with-fpu=fpv5-sp-d16"
				elif use fpu_fp-armv8; then				confgcc+=" --with-fpu=fp-armv8"
				elif use fpu_neon-fp-armv8; then		confgcc+=" --with-fpu=neon-fp-armv8"
				elif use fpu_crypto-neon-fp-armv8; then	confgcc+=" --with-fpu=crypto-neon-fp-armv8"
				else
					if [[ ${CTARGET} == armv6* ]]; then
						confgcc+=" --with-fpu=vfp"
					elif [[ ${CTARGET} == armv7* ]]; then
						confgcc+=" --with-fpu=vfpv3-d16"
					else
						confgcc+=" --with-fpu=fp-armv8"
					fi					
				fi
			fi
			float="hard"
		fi
		confgcc+=" --with-float=$float"
	fi

	local branding="Funtoo"
	if use hardened; then
		branding="$branding Hardened ${PVR}, pie-${PIE_VER}"
	else
		branding="$branding ${PVR}"
	fi

	cd ${WORKDIR}/objdir && ../gcc-${PV}/configure \
		$(use_enable libssp) \
		$(use_enable multilib) \
		--enable-version-specific-runtime-libs \
		--enable-libmudflap \
		--prefix=${PREFIX} \
		--bindir=${BINPATH} \
		--includedir=${LIBPATH}/include \
		--datadir=${DATAPATH} \
		--mandir=${DATAPATH}/man \
		--infodir=${DATAPATH}/info \
		--with-gxx-include-dir=${STDCXX_INCDIR} \
		--enable-clocale=gnu \
		--host=$CHOST \
		--build=$CHOST \
		--disable-ppl \
		--disable-cloog \
		--with-system-zlib \
		--enable-obsolete \
		--disable-werror \
		--enable-secureplt \
		--enable-lto \
		--with-bugurl=http://bugs.funtoo.org \
		--with-pkgversion="$branding" \
		--with-mpfr-include=${S}/mpfr/src \
		--with-mpfr-lib=${WORKDIR}/objdir/mpfr/src/.libs \
		$confgcc \
		|| die "configure fail"

	# The --with-mpfr* lines above are used so that gcc-4.6.4 can find mpfr-3.1.2.
	# It can find 2.4.2 with no problem automatically but needs help with newer versions
	# due to mpfr dir structure changes. We look for includes in the source directory,
	# and libraries in the build (objdir) directory.

#	if use arm ; then
# That fails miserably when cross-compiling on armv7a
	if use arm && ! is_crosscompile; then
		# Source : https://sourceware.org/bugzilla/attachment.cgi?id=6807
		# Workaround for a problem introduced with GMP 5.1.0.
		# If configured by gcc with the "none" host & target, it will result in undefined references
		# to '__gmpn_invert_limb' during linking.
		# Should be fixed by next version of gcc.
		sed -i "s/none-/${arm_arch_without_dash}-/" ${WORKDIR}/objdir/Makefile || die
	elif use arm && is_crosscompile; then		
		sed -i "s/none-/${CHOST%%-*}-/g" ${WORKDIR}/objdir/Makefile || die	
	fi

}

src_compile() {
	cd $WORKDIR/objdir
	unset ABI

	if is_crosscompile || tc-is-cross-compiler; then
		emake LIBPATH="${LIBPATH}" all || die "compile fail"
	else
		emake LIBPATH="${LIBPATH}" bootstrap-lean || die "compile fail"
	fi
}

create_gcc_env_entry() {
	dodir /etc/env.d/gcc
	local gcc_envd_base="/etc/env.d/gcc/${CTARGET}-${GCC_CONFIG_VER}"
	local gcc_envd_file="${D}${gcc_envd_base}"
	if [ -z $1 ]; then
		gcc_specs_file=""
	else
		gcc_envd_file="$gcc_envd_file-$1"
		gcc_specs_file="${LIBPATH}/$1.specs"
	fi
	cat <<-EOF > ${gcc_envd_file}
	GCC_PATH="${BINPATH}"
	LDPATH="${LIBPATH}:${LIBPATH}/32"
	MANPATH="${DATAPATH}/man"
	INFOPATH="${DATAPATH}/info"
	STDCXX_INCDIR="${STDCXX_INCDIR##*/}"
	GCC_SPECS="${gcc_specs_file}"
	EOF

	if is_crosscompile; then
		echo "CTARGET=\"${CTARGET}\"" >> ${gcc_envd_file}
	fi
}

linkify_compiler_binaries() {
	dodir /usr/bin
	cd "${D}"${BINPATH}
	# Ugh: we really need to auto-detect this list.
	#      It's constantly out of date.

	local binary_languages="cpp gcc g++ c++ gcov"

	use go && binary_languages="${binary_languages} gccgo"
	use fortran && binary_languages="${binary_languages} gfortran"

	for x in ${binary_languages} ; do
		[[ -f ${x} ]] && mv ${x} ${CTARGET}-${x}

		if [[ -f ${CTARGET}-${x} ]] ; then
			if ! is_crosscompile; then
				ln -sf ${CTARGET}-${x} ${x}
				dosym ${BINPATH}/${CTARGET}-${x} /usr/bin/${x}-${GCC_CONFIG_VER}
			fi
			# Create version-ed symlinks
			dosym ${BINPATH}/${CTARGET}-${x} /usr/bin/${CTARGET}-${x}-${GCC_CONFIG_VER}
		fi

		if [[ -f ${CTARGET}-${x}-${GCC_CONFIG_VER} ]] ; then
			rm -f ${CTARGET}-${x}-${GCC_CONFIG_VER}
			ln -sf ${CTARGET}-${x} ${CTARGET}-${x}-${GCC_CONFIG_VER}
		fi
	done
}

tasteful_stripping() {
	# Now do the fun stripping stuff
	env RESTRICT="" CHOST=${CHOST} prepstrip "${D}${BINPATH}"
	env RESTRICT="" CHOST=${CTARGET} prepstrip "${D}${LIBPATH}"
	# gcc used to install helper binaries in lib/ but then moved to libexec/
	[[ -d ${D}${PREFIX}/libexec/gcc ]] && \
		env RESTRICT="" CHOST=${CHOST} prepstrip "${D}${PREFIX}/libexec/gcc/${CTARGET}/${GCC_CONFIG_VER}"
}

doc_cleanups() {
	local cxx_mandir=$(find "${WORKDIR}/objdir/${CTARGET}/libstdc++-v3" -name man)
	if [[ -d ${cxx_mandir} ]] ; then
		# clean bogus manpages #113902
		find "${cxx_mandir}" -name '*_build_*' -exec rm {} \;
		cp -r "${cxx_mandir}"/man? "${D}/${DATAPATH}"/man/
	fi
	has noinfo ${FEATURES} \
		&& rm -r "${D}/${DATAPATH}"/info \
		|| prepinfo "${DATAPATH}"
	has noman ${FEATURES} \
		&& rm -r "${D}/${DATAPATH}"/man \
		|| prepman "${DATAPATH}"
}

src_install() {
	S=$WORKDIR/objdir; cd $S

# PRE-MAKE INSTALL SECTION:

	# from toolchain eclass:
	# Do allow symlinks in private gcc include dir as this can break the build
	find gcc/include*/ -type l -delete

	# Remove generated headers, as they can cause things to break
	# (ncurses, openssl, etc).
	while read x; do
		grep -q 'It has been auto-edited by fixincludes from' "${x}" \
			&& echo "Removing auto-generated header: $x" \
			&& rm -f "${x}"
	done < <(find gcc/include*/ -name '*.h')

# MAKE INSTALL SECTION:

	make -j1 DESTDIR="${D}" install || die

# POST MAKE INSTALL SECTION:

	# Basic sanity check
	if ! is_crosscompile; then
		local EXEEXT
		eval $(grep ^EXEEXT= "${WORKDIR}"/objdir/gcc/config.log)
		[[ -r ${D}${BINPATH}/gcc${EXEEXT} ]] || die "gcc not found in ${D}"
	fi

# GENTOO ENV SETUP
	if is_crosscompile; then
		if ! has_version ${CATEGORY}/${needed_libc} || built_with_use --hidden --missing false ${CATEGORY}/${needed_libc} crosscompile_opts_headers-only; then
			# not cruft!  glibc needs this for 2nd (real) pass else it fails, we'll delete it on gcc 2nd pass
			dodir /etc/env.d
			echo -e "PATH=/usr/${CHOST}/${CTARGET}/gcc-bin/${PV}\nROOTPATH=/usr/${CHOST}/${CTARGET}/gcc-bin/${PV}" > \
				"${D}"/etc/env.d/05gcc-${CTARGET}
		fi
	fi
	dodir /etc/env.d/gcc
	create_gcc_env_entry

	if use hardened; then
		create_gcc_env_entry hardenednopiessp
		create_gcc_env_entry hardenednopie
		create_gcc_env_entry hardenednossp
		create_gcc_env_entry vanilla
		insinto ${LIBPATH}
		doins "${WORKDIR}"/specs/*.specs
	fi

# CLEANUPS:

	# Punt some tools which are really only useful while building gcc
	find "${D}" -name install-tools -prune -type d -exec rm -rf "{}" \;
	# This one comes with binutils
	find "${D}" -name libiberty.a -delete
	# prune empty dirs left behind
	find "${D}" -depth -type d -delete 2>/dev/null
	# ownership fix:
	chown -R root:0 "${D}"${LIBPATH} 2>/dev/null

	linkify_compiler_binaries
	tasteful_stripping
	if is_crosscompile; then
		rm -rf "${D}"/usr/share/{man,info}
		rm -rf "${D}"${DATAPATH}/{man,info}
	else
		find "${D}/${LIBPATH}" -name libstdc++.la -type f -exec rm "{}" \;
		find "${D}/${LIBPATH}" -name "*.py" -type f -exec rm "{}" \;
		doc_cleanups
		exeinto "${DATAPATH}"
		doexe "${FILESDIR}"/c{89,99} || die
	fi

	# Don't scan .gox files for executable stacks - false positives
	if use go; then
		export QA_EXECSTACK="usr/lib*/go/*/*.gox"
		export QA_WX_LOAD="usr/lib*/go/*/*.gox"
	fi

	# Disable RANDMMAP so PCH works.
	pax-mark -r "${D}${PREFIX}/libexec/gcc/${CTARGET}/${GCC_CONFIG_VER}/cc1"
	pax-mark -r "${D}${PREFIX}/libexec/gcc/${CTARGET}/${GCC_CONFIG_VER}/cc1plus"
}

pkg_postrm() {
	# clean up the cruft left behind by cross-compilers
	if is_crosscompile ; then
		if [[ -z $(ls "${ROOT}"/etc/env.d/gcc/${CTARGET}* 2>/dev/null) ]] ; then
			rm -f "${ROOT}"/etc/env.d/gcc/config-${CTARGET}
			rm -f "${ROOT}"/etc/env.d/??gcc-${CTARGET}
			if ! built_with_use --hidden --missing false ${CATEGORY}/${needed_libc} crosscompile_opts_headers-only; then
				rm -f "${ROOT}"/etc/env.d/??gcc-${CTARGET}
			fi				
			rm -f "${ROOT}"/usr/bin/${CTARGET}-{gcc,{g,c}++}{,32,64}
		fi
		return 0
	fi
}

pkg_postinst() {
	if is_crosscompile ; then
		return
	fi

	# Here, we will auto-enable the new compiler if none is currently enabled, or
	# if this is an _._.x upgrade to an already-installed compiler.

	# One exception is if multislot is enabled in USE, which allows ie. 4.6.9
	# and 4.6.10 to exist alongside one another. In this case, the user must
	# enable this compiler manually.

	local do_config="yes"
	curr_gcc_config=$(env -i ROOT="${ROOT}" gcc-config -c ${CTARGET} 2>/dev/null)
	if [ -n "$curr_gcc_config" ]; then
		CURR_GCC_CONFIG_VER="$(gcc-config -S ${curr_gcc_config} | awk '{print $2}')"
		CURR_MAJOR="${CURR_GCC_CONFIG_VER%%.*}"
		MAJOR="${GCC_CONFIG_VER%%.*}"
		if [ "${CURR_MAJOR}" -gt "${MAJOR}" ]; then
			do_config="yes"
		elif [ "${CURR_MAJOR}" -lt "${MAJOR}" ]; then
			do_config="no"
		else
			# major versions match -- but if minor version of existing is greater, don't do gcc config
			CURR_MINOR="${CURR_MAJOR%%.*}"
			MINOR="${MAJOR%%.*}"
			if [ "${CURR_MINOR}" -gt "${MINOR}" ]; then
				do_config="yes"
			elif [ "${CURR_MINOR}" -lt "${MINOR}" ]; then
				do_config="no"
			else
				# minor versions match -- look at the x.x.Z release to figure out whether to auto-enable
				CURR_REL="${CURR_MINOR%%.*}"
				REL="${MINOR%%.}"
				if [ "${CURR_REL}" -gt "${REL}" ]; then
					do_config="yes"
				elif [ "${CURR_REL}" -gt "${REL}" ]; then
					do_config="no"
				fi
			fi
		fi
	fi

	if [ "$do_config" == "yes" ]; then
		gcc-config ${CTARGET}-${GCC_CONFIG_VER}
	else
		einfo "This does not appear to be a regular upgrade of gcc, so"
		einfo "gcc ${GCC_CONFIG_VER} will not be automatically enabled as the"
		einfo "default system compiler."
		echo
		einfo "If you would like to make ${GCC_CONFIG_VER} the default system"
		einfo "compiler, then perform the following steps as root:"
		echo
		einfo "gcc-config ${CTARGET}-${GCC_CONFIG_VER}"
		einfo "source /etc/profile"
		echo
	fi
}
