#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/i2c.h>
#include <linux/mfd/axp20x.h>
#include <linux/of.h>

static struct platform_device *adc_pdev;
static struct platform_device *bat_pdev;
static struct platform_device *ac_pdev;

static int is_axp221(struct device *dev, const void *data)
{
    struct i2c_client *client = i2c_verify_client(dev);
    if (!client)
        return 0;
    
    return of_device_is_compatible(client->dev.of_node, "x-powers,axp221");
}

static int __init uconsole_fixup_init(void)
{
    struct device *parent;
    struct device_node *np;
    struct device_node *child;

    // Find the AXP221 I2C client robustly
    parent = bus_find_device(&i2c_bus_type, NULL, NULL, is_axp221);
    if (!parent) {
        pr_err("uconsole-fixup: Could not find AXP221 I2C device by compatible string\n");
        return -ENODEV;
    }
    
    pr_info("uconsole-fixup: Found parent %s\n", dev_name(parent));
    np = parent->of_node;

    // --- Create ADC device ---
    adc_pdev = platform_device_alloc("axp20x-adc", -1);
    if (adc_pdev) {
        adc_pdev->dev.parent = parent;
        if (np) {
            for_each_child_of_node(np, child) {
                if (of_node_name_eq(child, "adc")) {
                     adc_pdev->dev.of_node = child;
                     pr_info("uconsole-fixup: Linked ADC OF node\n");
                     break;
                }
            }
        }
        if (platform_device_add(adc_pdev)) {
            pr_err("uconsole-fixup: Failed to add ADC device\n");
            platform_device_put(adc_pdev);
            adc_pdev = NULL;
        } else {
            pr_info("uconsole-fixup: Registered axp20x-adc\n");
        }
    }

    // --- Create Battery device ---
    // Matches the driver name in extracted-drivers/axp20x_battery.c
    bat_pdev = platform_device_alloc("axp20x-battery-power-supply", -1);
    if (bat_pdev) {
        bat_pdev->dev.parent = parent;
        if (np) {
            for_each_child_of_node(np, child) {
                if (of_node_name_eq(child, "battery-power-supply")) {
                     bat_pdev->dev.of_node = child;
                     pr_info("uconsole-fixup: Linked Battery OF node\n");
                     break;
                }
            }
        }
        if (platform_device_add(bat_pdev)) {
            pr_err("uconsole-fixup: Failed to add Battery device\n");
            platform_device_put(bat_pdev);
            bat_pdev = NULL;
        } else {
            pr_info("uconsole-fixup: Registered axp20x-battery-power-supply\n");
        }
    }

    /* --- Create AC Power device ---
     * Disabled: Causes IRQ error spam on TTY because IRQ resources are not 
     * correctly passed to manually registered platform device.
    ac_pdev = platform_device_alloc("axp20x-ac-power-supply", -1);
    if (ac_pdev) {
        ac_pdev->dev.parent = parent;
        if (np) {
            for_each_child_of_node(np, child) {
                if (of_node_name_eq(child, "ac_power_supply")) {
                     ac_pdev->dev.of_node = child;
                     pr_info("uconsole-fixup: Linked AC Power OF node\n");
                     break;
                }
            }
        }
        if (platform_device_add(ac_pdev)) {
            pr_err("uconsole-fixup: Failed to add AC Power device\n");
            platform_device_put(ac_pdev);
            ac_pdev = NULL;
        } else {
            pr_info("uconsole-fixup: Registered axp20x-ac-power-supply\n");
        }
    }
    */

    put_device(parent);
    return 0;
}

static void __exit uconsole_fixup_exit(void)
{
    if (adc_pdev) platform_device_unregister(adc_pdev);
    if (bat_pdev) platform_device_unregister(bat_pdev);
    if (ac_pdev) platform_device_unregister(ac_pdev);
}

module_init(uconsole_fixup_init);
module_exit(uconsole_fixup_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Fixup module to instantiate AXP221 child devices on uConsole CM5");
