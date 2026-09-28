package com.kama.jchatmind.demo;

import java.math.BigDecimal;
import org.springframework.ai.tool.annotation.Tool;

/** Pure arithmetic, scoped to the guest runtime. Prices must first come from retrieval. */
public class DemoPricingTool {
    @Tool(name = "calculateMonthlyCost", description = "Calculate monthly cost exactly. First retrieve the per-user monthly USD price from the handbook. Supply the requested user count and that price. Returns an exact equation before taxes; performs no billing action.")
    public String calculateMonthlyCost(int users, BigDecimal monthlyPriceUsd) {
        if (users < 1 || users > 100000 || monthlyPriceUsd == null
                || monthlyPriceUsd.signum() < 0 || monthlyPriceUsd.compareTo(new BigDecimal("100000")) > 0
                || monthlyPriceUsd.scale() > 2) {
            return "Invalid pricing inputs. Use 1–100000 users and a documented nonnegative USD price with at most two decimal places.";
        }
        BigDecimal total = monthlyPriceUsd.multiply(BigDecimal.valueOf(users));
        return users + " users × USD " + monthlyPriceUsd.stripTrailingZeros().toPlainString()
                + " per user/month = USD " + total.stripTrailingZeros().toPlainString()
                + " per month, before taxes. Arithmetic only; verify the rate against the retrieved handbook.";
    }
}
