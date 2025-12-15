obj-m := drm-rp1-dsi.o
drm-rp1-dsi-y := rp1_dsi.o rp1_dsi_dma.o rp1_dsi_dsi.o

# Add local include path for rp1_platform.h
ccflags-y += -I$(src)

KERNELDIR ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) clean
