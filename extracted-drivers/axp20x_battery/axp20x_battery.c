#define AXP20X_PWR_STATUS_BAT_CHARGING BIT(2)
#define AXP717_PWR_STATUS_MASK GENMASK(6, 5)
#define AXP717_PWR_STATUS_BAT_STANDBY 0
#define AXP717_PWR_STATUS_BAT_CHRG 1
#define AXP717_PWR_STATUS_BAT_DISCHRG 2

#define AXP20X_PWR_OP_BATT_PRESENT BIT(5)
#define AXP20X_PWR_OP_BATT_ACTIVATED BIT(3)
#define AXP717_PWR_OP_BATT_PRESENT BIT(3)

#define AXP717_BATT_PMU_FAULT_MASK GENMASK(2, 0)
#define AXP717_BATT_UVLO_2_5V BIT(2)
#define AXP717_BATT_OVER_TEMP BIT(1)
#define AXP717_BATT_UNDER_TEMP BIT(0)

#define AXP209_FG_PERCENT GENMASK(6, 0)
#define AXP22X_FG_VALID BIT(7)

#define AXP20X_CHRG_CTRL1_ENABLE BIT(7)
#define AXP20X_CHRG_CTRL1_TGT_VOLT GENMASK(6, 5)
#define AXP20X_CHRG_CTRL1_TGT_4_1V (0 << 5)
#define AXP20X_CHRG_CTRL1_TGT_4_15V (1 << 5)
#define AXP20X_CHRG_CTRL1_TGT_4_2V (2 << 5)
#define AXP20X_CHRG_CTRL1_TGT_4_36V (3 << 5)

#define AXP22X_CHRG_CTRL1_TGT_4_22V (1 << 5)
#define AXP22X_CHRG_CTRL1_TGT_4_24V (3 << 5)

#define AXP717_CHRG_ENABLE BIT(1)
#define AXP717_CHRG_CV_VOLT_MASK GENMASK(2, 0)
#define AXP717_CHRG_CV_4_0V 0
#define AXP717_CHRG_CV_4_1V 1
#define AXP717_CHRG_CV_4_2V 2
#define AXP717_CHRG_CV_4_35V 3
#define AXP717_CHRG_CV_4_4V 4
#define AXP717_CHRG_CV_5_0V 7
#define AXP813_CHRG_CTRL1_TGT_4_35V (3 << 5)
#define AXP20X_CHRG_CTRL1_TGT_CURR GENMASK(3, 0)
#define AXP717_ICC_CHARGER_LIM_MASK GENMASK(5, 0)
#define AXP717_ITERM_CHG_LIM_MASK GENMASK(3, 0)
#define AXP717_ITERM_CC_STEP 64000
#define AXP20X_V_OFF_MASK GENMASK(2, 0)
#define AXP717_V_OFF_MASK GENMASK(6, 4)
#define AXP228_FULL_CAPACITY_CALIBRATE_EN BIT(5)
#define AXP228_CAPACITY_CALIBRATE BIT(4)
#define AXP228_CALIBRATE_MASK (BIT(4) | BIT(5))
#define AXP717_BAT_VMIN_MIN_UV 2600000
#define AXP717_BAT_VMIN_MAX_UV 3300000
#define AXP717_BAT_VMIN_STEP 100000
#define AXP717_BAT_CV_MIN_UV 4000000
#define AXP717_BAT_CV_MAX_UV 5000000
#define AXP717_BAT_CC_MIN_UA 0
#define AXP717_BAT_CC_MAX_UA 3008000
	int ccc_scale;
	int ccc_offset;
	unsigned int ccc_reg;
	unsigned int ccc_mask;
	bool has_fg_valid;
	const struct power_supply_desc *bat_ps_desc;
	int (*get_max_voltage)(struct axp20x_batt_ps *batt, int *val);
	int (*set_max_voltage)(struct axp20x_batt_ps *batt, int val);
	int (*cfg_iio_chan)(struct platform_device *pdev,
			    struct axp20x_batt_ps *axp_batt);
	void (*set_bat_info)(struct platform_device *pdev,
			     struct axp20x_batt_ps *axp_batt,
			     struct power_supply_battery_info *info);
	int energy_full_design;
	int current_now;
	int voltage_now;
	const struct axp_data *data;
	       axp->data->ccc_scale;
			ret = iio_read_channel_processed(
				axp20x_batt->batt_chrg_i, &val->intval);
			ret = iio_read_channel_processed(
				axp20x_batt->batt_dischrg_i, &val1);
		axp20x_batt->current_now = val->intval;

		axp20x_batt->current_now = val->intval;

		break;

	case POWER_SUPPLY_PROP_ENERGY_FULL:
	case POWER_SUPPLY_PROP_ENERGY_NOW:
	case POWER_SUPPLY_PROP_ENERGY_FULL_DESIGN:
		/* When no battery is present, return 0 */
		ret = regmap_read(axp20x_batt->regmap, AXP20X_PWR_OP_MODE,
				  &reg);
		if (ret)
			return ret;

		if (!(reg & AXP20X_PWR_OP_BATT_PRESENT)) {
			val->intval = 0;
			return 0;
		}

		if (psp == POWER_SUPPLY_PROP_ENERGY_FULL) {
			// TODO
			val->intval = axp20x_batt->energy_full_design;
			return 0;
		}

		if (psp == POWER_SUPPLY_PROP_ENERGY_FULL_DESIGN) {
			val->intval = axp20x_batt->energy_full_design;
			return 0;
		}

		ret = regmap_read(axp20x_batt->regmap, AXP20X_FG_RES, &reg);
		if (ret)
			return ret;

		if (axp20x_batt->data->has_fg_valid && !(reg & AXP22X_FG_VALID))
			return -EINVAL;

		val1 = reg & AXP209_FG_PERCENT;
		val1 = max(min(val1, 100), 0);
		val->intval =
			(val1 *
			 ((long long int)axp20x_batt->energy_full_design)) /
			100;
		break;

	case POWER_SUPPLY_PROP_CALIBRATE:
		// report both calibrate enable flag and calibration status
		ret = regmap_read(axp20x_batt->regmap, AXP20X_CC_CTRL, &reg);
		if (ret)
			return ret;
		val1 = reg & AXP228_CALIBRATE_MASK;
		val->intval = val1;
		break;

	case POWER_SUPPLY_PROP_POWER_NOW:
		val->intval = (axp20x_batt->voltage_now / 10000) *
			      axp20x_batt->current_now;
		val->intval = val->intval / 100; // uW
		ret = regmap_read(axp20x_batt->regmap, AXP717_PMU_FAULT, &reg);
		ret = iio_read_channel_processed(axp20x_batt->batt_chrg_i,
						 &val->intval);
		ret = regmap_read(axp20x_batt->regmap, AXP717_BATT_PERCENT_DATA,
				  &reg);
		ret = regmap_read(axp20x_batt->regmap, AXP717_VSYS_V_POWEROFF,
				  &reg);
		val->intval = AXP717_BAT_VMIN_MIN_UV +
			      AXP717_BAT_VMIN_STEP * (reg & AXP717_V_OFF_MASK);
		ret = regmap_read(axp20x_batt->regmap, AXP717_ITERM_CHG_SET,
				  &reg);
		val->intval = (reg & AXP717_ITERM_CHG_LIM_MASK) *
			      AXP717_ITERM_CC_STEP;
	return regmap_update_bits(axp20x_batt->regmap, AXP717_CV_CHG_SET,
			 axp_batt->data->ccc_scale;
	val = (charge_current - axp->data->ccc_offset) / axp->data->ccc_scale;
	charge_current =
		(charge_current - axp->data->ccc_offset) / axp->data->ccc_scale;
	charge_current =
		charge_current * axp->data->ccc_scale + axp->data->ccc_offset;
		dev_warn(
			axp->dev,
			"Setting max constant charge current higher than previously defined. Note that increasing the constant charge current may damage your battery.\n");
	int val1 =
		(min_voltage - AXP717_BAT_VMIN_MIN_UV) / AXP717_BAT_VMIN_STEP;
	return regmap_update_bits(axp_batt->regmap, AXP717_VSYS_V_POWEROFF,
	int val1;
		return axp20x_batt->data->set_max_voltage(axp20x_batt,
							  val->intval);
	case POWER_SUPPLY_PROP_CALIBRATE:
		if (val->intval) {
			// enable calibrate
			val1 = AXP228_FULL_CAPACITY_CALIBRATE_EN |
			       AXP228_CAPACITY_CALIBRATE;
		} else {
			// disable calibrate
			val1 = 0;
		}
		return regmap_update_bits(axp20x_batt->regmap, AXP20X_CC_CTRL,
					  AXP228_CALIBRATE_MASK, val1);
			return regmap_update_bits(axp20x_batt->regmap,
						  AXP20X_CHRG_CTRL1,
						  AXP20X_CHRG_CTRL1_ENABLE,
						  AXP20X_CHRG_CTRL1_ENABLE);
			return regmap_update_bits(axp20x_batt->regmap,
						  AXP20X_CHRG_CTRL1,
						  AXP20X_CHRG_CTRL1_ENABLE, 0);
		return axp20x_batt->data->set_max_voltage(axp20x_batt,
							  val->intval);
	POWER_SUPPLY_PROP_ENERGY_FULL,
	POWER_SUPPLY_PROP_ENERGY_NOW,
	POWER_SUPPLY_PROP_ENERGY_FULL_DESIGN,
	POWER_SUPPLY_PROP_CALIBRATE,
	POWER_SUPPLY_PROP_POWER_NOW,
	       psp == POWER_SUPPLY_PROP_CONSTANT_CHARGE_CURRENT_MAX ||
	       psp == POWER_SUPPLY_PROP_CALIBRATE;
	axp_batt->batt_chrg_i = devm_iio_channel_get(&pdev->dev, "batt_chrg_i");
	axp_batt->batt_dischrg_i =
		devm_iio_channel_get(&pdev->dev, "batt_dischrg_i");
	axp_batt->batt_chrg_i = devm_iio_channel_get(&pdev->dev, "batt_chrg_i");
		dev_err(&pdev->dev, "couldn't set voltage_min_design\n");
		dev_err(&pdev->dev, "couldn't set voltage_min_design\n");
		dev_err(&pdev->dev, "couldn't set voltage_max_design\n");
			"couldn't set ccc from DT: current ccc is %d\n", val);
	},
	{
	},
	{
	},
	{
	},
	{ /* sentinel */ },
	axp20x_batt =
		devm_kzalloc(&pdev->dev, sizeof(*axp20x_batt), GFP_KERNEL);
	axp20x_batt->batt = devm_power_supply_register(
		&pdev->dev, axp20x_batt->data->bat_ps_desc, &psy_cfg);
		axp20x_batt->energy_full_design = info->energy_full_design_uwh;

		int cfd = info->charge_full_design_uah;

		// tell pmic about our battery
		if (cfd) {
			// [14:8], [7:0], cfd = Value * 1.456mAh
			cfd = cfd / 1456;
			regmap_update_bits(axp20x_batt->regmap,
					   AXP288_FG_DES_CAP0_REG, 0xff,
					   cfd & 0xff);
			regmap_update_bits(axp20x_batt->regmap,
					   AXP288_FG_DES_CAP1_REG, 0xff,
					   BIT(7) | ((cfd >> 8) & 0xff));
		} else {
			dev_warn(axp20x_batt->dev,
				 "charge full design is not set");
		}
	} else {
		axp20x_batt->energy_full_design = 8000000;
		dev_warn(axp20x_batt->dev,
			 "energy full design is not set, default to %d\n",
			 axp20x_batt->energy_full_design);
	regmap_update_bits(axp20x_batt->regmap, AXP20X_VBUS_IPSOUT_MGMT, 0x03, 0x03);
	regmap_update_bits(axp20x_batt->regmap, AXP20X_OFF_CTRL, 0x08, 0x08);
	regmap_update_bits(axp20x_batt->regmap, AXP20X_CHRG_CTRL2, 0x30, 0x20);
	regmap_update_bits(axp20x_batt->regmap, AXP20X_PEK_KEY, 0x0f, 0x0b);
	regmap_update_bits(axp20x_batt->regmap, AXP20X_GPIO0_CTRL, 0x07, 0x00);

