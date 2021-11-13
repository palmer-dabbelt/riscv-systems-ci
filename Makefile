.SECONDARY:

# This top-level Makefile itself just builds a bunch of tools, the actual tests
# are loaded later.  This default target reports the result of the test suite's
# run.
.PHONY: report
report: check
	tools/report

# Acutally runs the tests.  This itself doesn't really do much, it's just a
# redirect to run every test.
.PHONY: check
check:

# Cleans everything up
.PHONY: clean
clean:
	tools/git-clean-recursive

# Builds GCC from the RISC-V integration repo
GCC = toolchain/install/bin/riscv64-unknown-linux-gcc
$(GCC): toolchain/install.stamp

PATH := $(abspath $(dir $(GCC))):$(PATH)
export PATH

toolchain/install.stamp: toolchain/Makefile
	$(MAKE) -C $(dir $<)
	date > $@

toolchain/Makefile: riscv-gnu-toolchain/configure
	mkdir -p $(dir $@)
	env -C $(dir $@) $(abspath $<) --prefix="$(abspath $(dir $@)/install)" --enable-linux

# Builds QEMU from git source.  There's been an attempt at detecting
# dependencies here, but nothing serious.
QEMU_RISCV64 = qemu/install/bin/qemu-system-riscv64
QEMU_RISCV32 = qemu/install/bin/qemu-system-riscv32

$(QEMU_RISCV32) $(QEMU_RISCV64): qemu/stamp
	touch -c $@

qemu/stamp: \
		$(shell git -C qemu ls-files --recurse-submodules | grep -v ' ' | sed 's@^@qemu/@' | xargs readlink -e)
	env -C $(dir $@) ./configure --prefix="$(abspath $(shell readlink -f $(dir $@)/install))" --target-list=riscv64-softmmu,riscv32-softmmu
	$(MAKE) -C $(dir $@)
	$(MAKE) -C $(dir $@) install
	date > $@

qemu/stamp-check: qemu/stamp
	$(MAKE) -C $(dir $@) -j8 check |& tee $@
	touch -c $@

## Explicitly adds the QEMU test cases to "make check"
#check: qemu/stamp-check

# Builds generic Linux images, which are just based on our defconfig.
kernel/%/arch/riscv/boot/Image: kernel/%/stamp
	touch -c $@

kernel/%/stamp: \
		kernel/%/.config \
		toolchain/install.stamp \
		$(shell git -C linux ls-files | sed 's@^@linux/@' | xargs readlink -e)
	$(MAKE) -C linux/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu-
	date > $@

kernel/rv64gc/defconfig/.config: \
		linux/arch/riscv/configs/defconfig \
		toolchain/install.stamp \
		$(shell git -C linux ls-files | sed 's@^@linux/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C linux/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- defconfig
	touch -c $@

kernel/rv32gc/defconfig/.config: \
		linux/arch/riscv/configs/rv32_defconfig \
		toolchain/install.stamp \
		$(shell git -C linux ls-files | sed 's@^@linux/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C linux/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- rv32_defconfig
	touch -c $@

kernel/rv64gc/%/.config: \
		configs/linux/% \
		linux/arch/riscv/configs/defconfig \
		toolchain/install.stamp \
		$(shell git -C linux ls-files | sed 's@^@linux/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C linux/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- defconfig
	cat $< >> $@
	$(MAKE) -C linux/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- olddefconfig
	touch -c $@

kernel/rv32gc/%/.config: \
		configs/linux/% \
		linux/arch/riscv/configs/rv32_defconfig \
		toolchain/install.stamp \
		$(shell git -C linux ls-files | sed 's@^@linux/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C linux/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- rv32_defconfig
	cat $< >> $@
	$(MAKE) -C linux/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- olddefconfig
	touch -c $@

kernel/rv64gc/all%config/.config: \
		$(shell git -C linux ls-files | sed 's@^@linux/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C linux/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- KCONFIG_ALLCONFIG=$(abspath linux/arch/riscv/configs/64-bit.config) $(word 3,$(subst /, ,$@))
	touch -c $@

kernel/rv32gc/all%config/.config: \
		$(shell git -C linux ls-files | sed 's@^@linux/@' | xargs readlink -e | grep Kconfig)
	mkdir -p $(dir $@)
	rm -f $@
	$(MAKE) -C linux/ O=$(abspath $(dir $@)) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- KCONFIG_ALLCONFIG=$(abspath linux/arch/riscv/configs/32-bit.config) $(word 3,$(subst /, ,$@))
	touch -c $@

# Explicitly adds some build-only kernel configs
check: kernel/rv32gc/defconfig/stamp
check: kernel/rv32gc/allnoconfig/stamp
check: kernel/rv32gc/allmodconfig/stamp
check: kernel/rv32gc/allyesconfig/stamp
check: kernel/rv64gc/defconfig/stamp
check: kernel/rv64gc/allnoconfig/stamp
check: kernel/rv64gc/allmodconfig/stamp
check: kernel/rv64gc/allyesconfig/stamp

# Builds generic buildroot images, which are also just based on our defconfig.
userspace/%/images/rootfs.cpio: userspace/%/stamp
	touch -c $@

userspace/%/stamp: userspace/%/.config
	$(MAKE) -C buildroot O=$(abspath $(dir $@))
	date > $@

userspace/rv64gc/default/.config: \
		$(shell git -C buildroot ls-files | sed 's@^@buildroot/@' | xargs readlink -e)
	mkdir -p $(dir $@)
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) qemu_riscv64_virt_defconfig
	echo "BR2_TARGET_ROOTFS_CPIO=y" >> $@
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) olddefconfig

userspace/rv32gc/default/.config: \
		$(shell git -C buildroot ls-files | sed 's@^@buildroot/@' | xargs readlink -e)
	mkdir -p $(dir $@)
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) qemu_riscv32_virt_defconfig
	echo "BR2_TARGET_ROOTFS_CPIO=y" >> $@
	$(MAKE) -C buildroot/ O=$(abspath $(dir $@)) olddefconfig

# Runs tests in QEMU, both in 32-bit mode and 64-bit mode.
TARGETS += qemu-rv64gc-virt-smp4
target/qemu-rv64gc-virt-smp4/run: tools/make-qemu-wrapper $(QEMU_RISCV64)
	mkdir -p $(dir $@)
	$< --output "$@" --machine virt --memory 8G --smp 4 --isa rv64 --qemu $(QEMU_RISCV64)

target/qemu-rv64gc-virt-smp4/kernel/%: kernel/rv64gc/%/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv64gc-virt-smp4/initrd/%: userspace/rv64gc/%/images/rootfs.cpio
	mkdir -p $(dir $@)
	cp $< $@

TARGETS += qemu-rv32gc-virt-smp4
target/qemu-rv32gc-virt-smp4/run: tools/make-qemu-wrapper $(QEMU_RISCV32)
	mkdir -p $(dir $@)
	$< --output "$@" --machine virt --memory 1G --smp 4 --isa rv32 --qemu $(QEMU_RISCV32)

target/qemu-rv32gc-virt-smp4/kernel/%: kernel/rv32gc/%/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv32gc-virt-smp4/initrd/%: userspace/rv32gc/%/images/rootfs.cpio
	mkdir -p $(dir $@)
	cp $< $@

# A HiFive Unleashed-like board
#TARGETS += qemu-rv64gc-h5u-smp5
target/qemu-rv64gc-h5u-smp5/run: tools/make-qemu-wrapper $(QEMU_RISCV64)
	mkdir -p $(dir $@)
	$< --output "$@" --machine sifive_u --memory 8G --smp 5 --isa rv64gcsu-v1.10.0 --qemu $(QEMU_RISCV64)

target/qemu-rv64gc-h5u-smp5/kernel/%: kernel/rv64gc/%/arch/riscv/boot/Image
	mkdir -p $(dir $@)
	cp $< $@

target/qemu-rv64gc-h5u-smp5/initrd/%: userspace/rv64gc/%/images/rootfs.cpio
	mkdir -p $(dir $@)
	cp $< $@

# Just halts the target.
define mktest =
TESTS += $1-$2

check/%/$1-$2/initrd: target/%/initrd/default
	mkdir -p $$(dir $$@)
	cp $$< $$@

check/%/$1-$2/kernel: target/%/kernel/$2
	mkdir -p $$(dir $$@)
	cp $$< $$@

check/%/$1-$2/stdin: tests/$1
	mkdir -p $$(dir $$@)
	cp $$< $$@
	touch -c $$@
endef

$(eval $(call mktest,halt,defconfig))
$(foreach config,$(patsubst configs/linux/%,%,$(wildcard configs/linux/*)), $(eval $(call mktest,halt,$(config))))

# Expands out the total list of tests
define expand =
check: check/$1/$2/stdout
check/$1/$2/stdout: target/$1/run check/$1/$2/kernel check/$1/$2/initrd check/$1/$2/stdin
	$$< --output $$@ $$^

check/$1/$2/log: check/$1/$2/stdout check/$1/$2/gold
	tools/check-log --output $$@ $$^
endef

$(foreach target,$(TARGETS),$(foreach test,$(TESTS), $(eval $(call expand,$(target),$(test)))))
