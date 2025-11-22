	regmap_update_bits(power->regmap, AXP20X_VBUS_IPSOUT_MGMT, 0x03, 0x00);
	regmap_update_bits(power->regmap, AXP20X_VBUS_IPSOUT_MGMT, 0x03, 0x03);

