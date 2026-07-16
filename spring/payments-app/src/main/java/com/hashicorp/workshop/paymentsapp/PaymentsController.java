package com.hashicorp.workshop.paymentsapp;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.*;

import javax.sql.DataSource;
import java.util.List;

/**
 * REST controller for the payments resource.
 *
 * <p>Demonstrates two aspects of the Vault Agent pattern:
 * <ol>
 *   <li><strong>Dynamic DB credentials</strong> — {@code GET /payments} queries the
 *       database using the HikariCP pool constructed from the Vault-issued
 *       short-lived credentials in the main application class.</li>
 *   <li><strong>Static KV secrets</strong> — {@code GET /payments/config} returns the
 *       current value of the static credentials so a tutorial learner can observe
 *       them being live-reloaded after a {@code vault kv put} update.</li>
 * </ol>
 *
 * <p>Neither endpoint performs real payment processing — they exist solely to
 * prove that credentials are wired up and live-reload works end-to-end.
 */
@RestController
@RequestMapping("/payments")
public class PaymentsController {

    private final JdbcClient db;
    private final ExampleClient client;

    public PaymentsController(DataSource dataSource, ExampleClient client) {
        this.db = JdbcClient.create(dataSource);
        this.client = client;
    }

    /**
     * Returns all payments from the database.
     * A successful response proves the dynamic DB credentials are valid and
     * the connection pool is healthy.
     */
    @GetMapping
    public ResponseEntity<List<Payment>> listPayments() {
        List<Payment> payments = db
                .sql("SELECT id, reference, amount, currency, status, created_at FROM payments")
                .query((rs, _) -> new Payment(
                        rs.getLong("id"),
                        rs.getString("reference"),
                        rs.getBigDecimal("amount"),
                        rs.getString("currency"),
                        rs.getString("status"),
                        rs.getObject("created_at", java.time.OffsetDateTime.class)
                ))
                .list();
        return ResponseEntity.ok(payments);
    }

    /**
     * Creates a sample payment — useful for seeding data during the tutorial.
     */
    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE,
                 produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Payment> createPayment(@RequestBody Payment payment) {
        Long id = db
                .sql("INSERT INTO payments(reference, amount, currency, status) "
                        + "VALUES(:reference, :amount, :currency, :status) RETURNING id")
                .param("reference", payment.reference())
                .param("amount", payment.amount())
                .param("currency", payment.currency() != null ? payment.currency() : "USD")
                .param("status", payment.status() != null ? payment.status() : "PENDING")
                .query((rs, _) -> rs.getLong("id"))
                .single();

        Payment created = db
                .sql("SELECT id, reference, amount, currency, status, created_at FROM payments WHERE id = :id")
                .param("id", id)
                .query((rs, _) -> new Payment(
                        rs.getLong("id"),
                        rs.getString("reference"),
                        rs.getBigDecimal("amount"),
                        rs.getString("currency"),
                        rs.getString("status"),
                        rs.getObject("created_at", java.time.OffsetDateTime.class)
                ))
                .single();
        return ResponseEntity.ok(created);
    }

    /**
     * Returns the current static credentials from the KV store.
     * Use this to verify live-reload: run {@code vault kv put spring/kv/payments-app
     * custom.static-secret.username=new-user custom.static-secret.password=new-pass},
     * wait for Vault Agent to re-render and call /actuator/refresh, then hit this
     * endpoint again to confirm the values have changed — without restarting the app.
     */
    @GetMapping("/secret")
    public ResponseEntity<AppProperties.StaticSecret> getStaticSecret() {
        return ResponseEntity.ok(client.getProperties().getStaticSecret());
    }
}
