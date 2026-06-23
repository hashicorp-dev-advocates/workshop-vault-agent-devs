package com.hashicorp.workshop.paymentsapp.repository;

import com.hashicorp.workshop.paymentsapp.model.Payment;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PaymentRepository extends JpaRepository<Payment, Long> {
}
