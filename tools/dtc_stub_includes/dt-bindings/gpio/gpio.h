/* SPDX-License-Identifier: GPL-2.0 */
/* Stub dt-bindings/gpio/gpio.h for DTS compilation */

#ifndef _DT_BINDINGS_GPIO_GPIO_H
#define _DT_BINDINGS_GPIO_GPIO_H

/* Bit 0 expresses the active level (high/low) */
#define GPIO_ACTIVE_HIGH 0
#define GPIO_ACTIVE_LOW 1

/* Bit 1 expresses single-ended mode */
#define GPIO_PUSH_PULL 0
#define GPIO_SINGLE_ENDED 2

/* Bit 2 expresses open-drain/open-source */
#define GPIO_LINE_OPEN_SOURCE 0
#define GPIO_LINE_OPEN_DRAIN 4

/* Open drain mode (combines single-ended + open-drain) */
#define GPIO_OPEN_DRAIN (GPIO_SINGLE_ENDED | GPIO_LINE_OPEN_DRAIN)
#define GPIO_OPEN_SOURCE (GPIO_SINGLE_ENDED | GPIO_LINE_OPEN_SOURCE)

/* Bit 3 expresses pull-up/pull-down mode */
#define GPIO_PULL_UP 8
#define GPIO_PULL_DOWN 16

/* Bit 4 expresses persistence across sleep */
#define GPIO_PERSISTENT 0
#define GPIO_TRANSITORY 32

#endif /* _DT_BINDINGS_GPIO_GPIO_H */
