-- =====================================================================
-- SMART BANKING & FUND TRANSFER SYSTEM
-- File: 02_triggers.sql
-- Description: Automated Triggers for Auditing and Business Rules
-- =====================================================================

-- Trigger 1: Automatically log any balance or status change into AUDIT_LOGS
CREATE OR REPLACE TRIGGER TRG_ACCOUNT_AUDIT
AFTER UPDATE OF balance, status ON ACCOUNTS
FOR EACH ROW
DECLARE
    v_action VARCHAR2(30);
BEGIN
    IF :OLD.balance <> :NEW.balance THEN
        IF :NEW.balance > :OLD.balance THEN
            v_action := 'CREDIT_UPDATE';
        ELSE
            v_action := 'DEBIT_UPDATE';
        END IF;
    ELSIF :OLD.status <> :NEW.status THEN
        v_action := 'STATUS_CHANGED_TO_' || :NEW.status;
    ELSE
        v_action := 'ACCOUNT_MODIFIED';
    END IF;

    INSERT INTO AUDIT_LOGS (
        log_id,
        account_no,
        action_type,
        old_balance,
        new_balance,
        changed_by,
        changed_at
    ) VALUES (
        SEQ_LOG_ID.NEXTVAL,
        :NEW.account_no,
        v_action,
        :OLD.balance,
        :NEW.balance,
        USER,
        CURRENT_TIMESTAMP
    );
END;
/

-- Trigger 2: Prevent deletion of an account if it still has an active balance
CREATE OR REPLACE TRIGGER TRG_PREVENT_DELETE_ACTIVE
BEFORE DELETE ON ACCOUNTS
FOR EACH ROW
BEGIN
    IF :OLD.balance > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20001, 
            'Cannot delete Account No: ' || :OLD.account_no || 
            '. Account still has an active balance of ₹' || :OLD.balance || 
            '. Please withdraw/transfer funds first.'
        );
    END IF;
END;
/
