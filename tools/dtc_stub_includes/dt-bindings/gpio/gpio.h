/* SPDX-License-Identifier: MIT */
/*
 * Minimal GPIO devicetree binding constants for DTS overlay compilation.
 * Values match the standardised devicetree GPIO flag definitions.
 */

#ifndef _DT_BINDINGS_GPIO_GPIO_H
#define _DT_BINDINGS_GPIO_GPIO_H

#define GPIO_ACTIVE_HIGH 0
#define GPIO_ACTIVE_LOW  1

#define GPIO_PUSH_PULL      0
#define GPIO_SINGLE_ENDED   2

#define GPIO_LINE_OPEN_SOURCE 0
#define GPIO_LINE_OPEN_DRAIN  4

#define GPIO_OPEN_DRAIN  (GPIO_SINGLE_ENDED | GPIO_LINE_OPEN_DRAIN)
#define GPIO_OPEN_SOURCE (GPIO_SINGLE_ENDED | GPIO_LINE_OPEN_SOURCE)

#define GPIO_PULL_UP   8
#define GPIO_PULL_DOWN 16

#define GPIO_PERSISTENT 0
#define GPIO_TRANSITORY 32

#endif /* _DT_BINDINGS_GPIO_GPIO_H */
