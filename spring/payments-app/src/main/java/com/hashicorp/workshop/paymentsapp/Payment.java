package com.hashicorp.workshop.paymentsapp;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

/**
 * Represents a payment record from the {@code payments} table.
 */
record Payment(
        @JsonProperty("id") Long id,
        @JsonProperty("reference") String reference,
        @JsonProperty("amount") BigDecimal amount,
        @JsonProperty("currency") String currency,
        @JsonProperty("status") String status,
        @JsonProperty("created_at") OffsetDateTime createdAt) {
}
