package com.hashicorp.workshop.paymentsapp.controller;

import com.hashicorp.workshop.paymentsapp.config.StaticSecretConfig;
import com.hashicorp.workshop.paymentsapp.model.Payment;
import com.hashicorp.workshop.paymentsapp.repository.PaymentRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

/**
 * REST controller for the payments resource.
 *
 * <p>Demonstrates two aspects of the Vault Agent pattern:
 * <ol>
 *   <li><strong>Dynamic DB credentials</strong> — {@code GET /payments} queries the
 *       database using the HikariCP pool constructed from the Vault-issued
 *       short-lived credentials in {@code DataSourceConfig}.</li>
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

    private final PaymentRepository repository;
    private final StaticSecretConfig staticSecretConfig;

    public PaymentsController(PaymentRepository repository,
                              StaticSecretConfig staticSecretConfig) {
        this.repository = repository;
        this.staticSecretConfig = staticSecretConfig;
    }

    /**
     * Returns all payments from the database.
     * A successful response proves the dynamic DB credentials are valid and
     * the connection pool is healthy.
     */
    @GetMapping
    public ResponseEntity<List<Payment>> listPayments() {
        return ResponseEntity.ok(repository.findAll());
    }

    /**
     * Creates a sample payment — useful for seeding data during the tutorial.
     */
    @PostMapping
    public ResponseEntity<Payment> createPayment(@RequestBody Payment payment) {
        return ResponseEntity.ok(repository.save(payment));
    }

    /**
     * Returns the current static credentials from the KV store.
     * Use this to verify live-reload: run {@code vault kv put spring/kv/payments-app
     * custom.StaticSecret.username=new-user custom.StaticSecret.password=new-pass},
     * wait for Vault Agent to re-render and call /actuator/refresh, then hit this
     * endpoint again to confirm the values have changed — without restarting the app.
     */
    @GetMapping("/config")
    public ResponseEntity<Map<String, String>> showConfig() {
        return ResponseEntity.ok(Map.of(
                "custom.static-secret.username", staticSecretConfig.getUsername(),
                "custom.static-secret.password", staticSecretConfig.getPassword()
        ));
    }
}
