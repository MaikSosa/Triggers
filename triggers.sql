
/* Delete a row from contact table. */
DELETE
FROM   contact
WHERE  last_name LIKE 'Smith_Wyse';

/* Delete a row from member table. */
DELETE
FROM   member
WHERE  account_number = 'SLC-000040';

/* Conditionally drop a trigger. */
DECLARE
  success  BOOLEAN := FALSE;
BEGIN
  FOR i IN (SELECT trigger_name
            FROM   user_triggers
            WHERE  trigger_name = 'CONTACT_T') LOOP
    EXECUTE IMMEDIATE 'DROP TRIGGER '||i.trigger_name;
	
    /* Set success to true. */
    success := TRUE;
	
    /* Print successful message. */
    dbms_output.put_line('Dropped trigger.');
  END LOOP;
  
  IF NOT success THEN
    /* Print successful message. */
    dbms_output.put_line('Failed to drop trigger ');
  END IF; 
END;
/

/* Conditionally insert row into the member table. */
DECLARE
  /* Declare a control variable to avoid duplicate inserts. */
  lv_member_id  NUMBER := 0;
  
    /* Convert the member account_number into a surrogate member_id value. */
  FUNCTION get_member_id
  ( pv_account_number  VARCHAR2 ) RETURN NUMBER IS
  
    /* Local return variable. */
    lv_retval  NUMBER := 0;  -- Default value is 0.
 
    /* A cursor that lookups up a member's ID by their name. */
    CURSOR find_member_id
    ( cv_account_number  VARCHAR2 ) IS
      SELECT   m.member_id
	  FROM     member m
	  WHERE    m.account_number = cv_account_number;
    
  BEGIN  
    /* 
     *  Write a FOR-LOOP that:
     *    Assign a member_id as the return value when a row exists.
     */
    FOR i IN find_member_id(pv_account_number) LOOP
      lv_retval := i.member_id;
    END LOOP;
 
    /* Return 0 when no row found and the member_id when a row is found. */
    RETURN lv_retval;
  END get_member_id;
  
BEGIN
  /* Check for and assign an existing surrogate key value. */
  lv_member_id := get_member_id('SLC-000040');

  /* Insert row when there is no prior row. */
  IF lv_member_id = 0 THEN
    /* Insert row into the member table. */
    INSERT
    INTO   member
    ( member_id
    , member_type
    , account_number
    , credit_card_number
    , credit_card_type
    , created_by
    , creation_date
    , last_updated_by
    , last_update_date )
    VALUES
    ( member_s1.nextval
    ,(SELECT   common_lookup_id
      FROM     common_lookup
      WHERE    common_lookup_table = 'MEMBER'
      AND      common_lookup_column = 'MEMBER_TYPE'
      AND      common_lookup_type = 'INDIVIDUAL')
    ,'SLC-000040'
    ,'6022-2222-3333-4444'
    ,(SELECT   common_lookup_id
      FROM     common_lookup
      WHERE    common_lookup_table = 'MEMBER'
      AND      common_lookup_column = 'CREDIT_CARD_TYPE'
      AND      common_lookup_type = 'DISCOVER_CARD')
    , 2
    , TRUNC(SYSDATE)
    , 2
    , TRUNC(SYSDATE));
  END IF;
END;
/

/* Conditionally drop a table and sequence. */
BEGIN
  FOR i IN (SELECT object_name
            ,      object_type
            FROM   user_objects
            WHERE  object_name IN ('CONTACT_LOG','CONTACT_LOG_SEQ')) LOOP
    IF i.object_type = 'TABLE' THEN
      EXECUTE IMMEDIATE 'DROP TABLE '||i.object_name||' CASCADE CONSTRAINTS';
    ELSE
      EXECUTE IMMEDIATE 'DROP SEQUENCE '||i.object_name;
    END IF;
  END LOOP;
END;
/

/* Create table contact_log table. */
CREATE TABLE contact_log
( contact_log_id  NUMBER
, trigger_name    VARCHAR(128)
, trigger_timing  VARCHAR(6)
, trigger_event   VARCHAR(12)
, trigger_type    VARCHAR(16)
, old_last_name   VARCHAR(30)
, new_last_name   VARCHAR(30));

/* Drop a sequence. */
DROP SEQUENCE IF EXISTS contact_log_seq;

/* Create a sequence. */
CREATE SEQUENCE contact_log_seq START WITH 1001;

/* Create or replace procedure. */
CREATE OR REPLACE
  PROCEDURE contact_log_p 
  ( pv_trigger_name    IN  VARCHAR2
  , pv_trigger_timing  IN  VARCHAR2
  , pv_trigger_event   IN  VARCHAR2
  , pv_trigger_type    IN  VARCHAR2
  , pv_old_last_name   IN  VARCHAR2
  , pv_new_last_name   IN  VARCHAR2 ) IS

    /* Set precompiler directive. */
    PRAGMA AUTONOMOUS_TRANSACTION; 
    
  BEGIN
    /* Insert into contact_log table. */ 
    INSERT INTO contact_log
    ( contact_log_id
    , trigger_name
    , trigger_timing
    , trigger_event
    , trigger_type
    , old_last_name
    , new_last_name )
    VALUES 
    ( contact_log_seq.nextval
    , pv_trigger_name
    , pv_trigger_timing
    , pv_trigger_event
    , pv_trigger_type
    , pv_old_last_name
    , pv_new_last_name );
    
    /* Commit the transaction. */
    COMMIT;
    
  EXCEPTION
    WHEN OTHERS THEN
	  ROLLBACK;
  END contact_log_p;
/

/* Create or replace trigger. */
CREATE OR REPLACE
  TRIGGER contact_t
  BEFORE INSERT OR UPDATE ON contact
  FOR EACH ROW
  WHEN (REGEXP_LIKE(new.last_name,' '))
  DECLARE
    lv_trigger_name VARCHAR2(30) := 'CONTACT_T';
    lv_trigger_timing VARCHAR2(6) := 'BEFORE';
    lv_trigger_event VARCHAR2(6);
    lv_trigger_type VARCHAR2(12) := 'FOR EACH ROW';
BEGIN
  IF INSERTING THEN
    /* Add the hyphen between the two part name. */
    :new.last_name := (REGEXP_REPLACE(:new.last_name,' ', '-'));
	
    lv_trigger_event := 'INSERT';
	/* Call procedure to insert the log values. */
	contact_log_p( 
      pv_trigger_name      => lv_trigger_name
    , pv_trigger_event     => lv_trigger_event
    , pv_trigger_type      => lv_trigger_type
    , pv_trigger_timing    => lv_trigger_timing
    , pv_old_last_name     => :old.last_name
    , pv_new_last_name     => :new.last_name );
    
  ELSIF UPDATING THEN
  	/* Call procedure to insert the log values. */
    lv_trigger_event := 'UPDATE';
	contact_log_p( 
      pv_trigger_name      => lv_trigger_name
    , pv_trigger_event     => lv_trigger_event
    , pv_trigger_type      => lv_trigger_type
    , pv_trigger_timing    => lv_trigger_timing
    , pv_old_last_name     => :old.last_name
    , pv_new_last_name     => :new.last_name );
	  
    /* Raise error to state policy allows no changes. */
    RAISE_APPLICATION_ERROR(-20001,'Whitespace replaced with hyphen.');
  END IF;	
END contact_t;
/

/* Insert into the contact table. */
INSERT INTO contact
  ( contact_id
  , member_id
  , contact_type
  , last_name
  , first_name
  , middle_name
  , created_by
  , creation_date
  , last_updated_by
  , last_update_date )
VALUES
  ( contact_s1.nextval
  , (SELECT member_id
     FROM   member
     WHERE  account_number = 'SLC-000040')
  , (SELECT common_lookup_id
     FROM   common_lookup
     WHERE  common_lookup_table = 'MEMBER'
     AND    common_lookup_column = 'MEMBER_TYPE'
     AND    common_lookup_type = 'INDIVIDUAL')
  , 'Smith Wyse'
  , 'Samuel'
  , NULL
  , 2
  , TRUNC(SYSDATE)
  , 2
  , TRUNC(SYSDATE));
  
  /* Verify that the multiword last name is hyphenated. */
SELECT last_name
FROM   contact
WHERE  last_name like 'Smith_Wyse';

/* Update contact table. */
UPDATE contact
SET    last_name = 'Smith Wyse'
WHERE  last_name = 'Smith-Wyse';

/* Verify two rows written to contact_log table. */
COL old_last_name FORMAT A12
COL new_last_name FORMAT A12
SELECT trigger_name
,      trigger_event
,      old_last_name
,      new_last_name
FROM   contact_log;

/* Query the last name entry of Smith-Wyse after trigger. */
SELECT c.last_name || ', ' || c.first_name AS full_name
FROM   contact c
WHERE  c.last_name LIKE 'Smith_Wyse';