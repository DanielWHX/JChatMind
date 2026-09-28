package com.kama.jchatmind.demo;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

class DemoPricingToolTest {
    private final DemoPricingTool tool = new DemoPricingTool();
    @Test void computesActualMonthlyPricesExactly() {
        assertThat(tool.calculateMonthlyCost(8, new BigDecimal("18"))).contains("USD 144 per month");
        assertThat(tool.calculateMonthlyCost(12, new BigDecimal("18"))).contains("USD 216 per month");
        assertThat(tool.calculateMonthlyCost(3, new BigDecimal("9.99"))).contains("USD 29.97 per month");
    }
    @Test void rejectsInvalidInputs() {
        assertThat(tool.calculateMonthlyCost(0, BigDecimal.TEN)).startsWith("Invalid");
        assertThat(tool.calculateMonthlyCost(8, new BigDecimal("-18"))).startsWith("Invalid");
        assertThat(tool.calculateMonthlyCost(8, new BigDecimal("1.001"))).startsWith("Invalid");
        assertThat(tool.calculateMonthlyCost(8, null)).startsWith("Invalid");
    }
}
