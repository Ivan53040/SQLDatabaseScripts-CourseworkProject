-- Q1.1
SELECT table_name, constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_name IN ('staff','dept','sales','customer')
ORDER BY table_name, constraint_name;

-- Q1.2

ALTER TABLE sales  
ADD CONSTRAINT pk_saleno      
PRIMARY KEY (saleno);

ALTER TABLE dept   
ADD CONSTRAINT un_dname       
UNIQUE (dname);

ALTER TABLE staff  
ADD CONSTRAINT ck_staffname   
CHECK (staffname IS NOT NULL AND staffname <> '');

ALTER TABLE dept   
ADD CONSTRAINT ck_dname       
CHECK (dname     IS NOT NULL AND dname     <> '');

ALTER TABLE customer 
ADD CONSTRAINT ck_cname     
CHECK (cname     IS NOT NULL AND cname     <> '');

ALTER TABLE sales  
ADD CONSTRAINT ck_receiptno   
CHECK (receiptno IS NOT NULL);

ALTER TABLE sales  
ADD CONSTRAINT ck_amount      
CHECK (amount > 0);

ALTER TABLE staff  
ADD CONSTRAINT ck_position    
CHECK (
  position IN ('Group Manager','Group Assistant','Group Member','Team Leader','Branch Manager')
);

ALTER TABLE sales    
ADD CONSTRAINT ck_servicetype 
CHECK (
  servicetype IN ('Software Installation','Software Repair','Training','Consultation','Data Recovery')
);

ALTER TABLE sales  
ADD CONSTRAINT ck_paymenttype 
CHECK (paymenttype IN ('Debit','Cash','Credit'));

ALTER TABLE sales  
ADD CONSTRAINT ck_gst         
CHECK (gst IN ('Yes','No'));

ALTER TABLE staff  
ADD CONSTRAINT fk_deptno      
FOREIGN KEY (deptno)     REFERENCES dept(deptno);

ALTER TABLE sales  
ADD CONSTRAINT fk_staffno     
FOREIGN KEY (servedby)   REFERENCES staff(staffno);

ALTER TABLE sales  
ADD CONSTRAINT fk_customerno  
FOREIGN KEY (customerno) REFERENCES customer(customerno);

-- Q2.1 sequence (idempotent)
CREATE SEQUENCE pno_seq
START WITH 10000
MINVALUE 10000
NO MAXVALUE
INCREMENT BY 1;

-- Q2.2
CREATE FUNCTION udf_bi_pno() 
RETURNS TRIGGER 
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.saleno IS NULL THEN 
    NEW.saleno := nextval('pno_seq'); 
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER BI_PNO 
BEFORE INSERT ON sales 
FOR EACH ROW 
EXECUTE FUNCTION udf_bi_pno();

-- Q2.3
CREATE FUNCTION udf_top_discount() 
RETURNS TRIGGER 
LANGUAGE plpgsql AS $$
DECLARE 
  top_customer INT;
  --find the top customer by calcuating the total amount of purhase they made
BEGIN
  SELECT customerno 
    INTO top_customer
    FROM sales 
  GROUP BY customerno 
  ORDER BY SUM(amount) DESC 
  LIMIT 1;
  
  IF top_customer IS NOT NULL AND NEW.customerno = top_customer THEN
    NEW.amount := NEW.amount * 0.85;
  END IF;

  RETURN NEW;
END $$;

CREATE TRIGGER top_discount 
BEFORE INSERT ON sales 
FOR EACH ROW 
EXECUTE FUNCTION udf_top_discount();

-- Q2.4
CREATE FUNCTION udf_sunshine_dept() 
RETURNS TRIGGER 
LANGUAGE plpgsql AS $$
DECLARE 
  v_is_sunshine boolean;
BEGIN
  --Check if the staff's deprartment is sunshine
  SELECT EXISTS (
        SELECT 1
          FROM staff s
          JOIN dept  d ON d.deptno = s.deptno
         WHERE s.staffno = NEW.servedby
           AND d.dname ILIKE '%Sunshine%'
    ) INTO v_is_sunshine;

  IF v_is_sunshine THEN
    NEW.paymenttype := 'Cash';
    IF NEW.servicetype = 'Data Recovery' THEN
      NEW.amount := NEW.amount * 0.70;
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER sunshine_dept 
BEFORE INSERT ON sales 
FOR EACH ROW 
EXECUTE FUNCTION udf_sunshine_dept();

-- Q2.5
CREATE FUNCTION UDF_TIME_CHECK() 
RETURNS TRIGGER 
LANGUAGE plpgsql AS $$
DECLARE
  prev_loc text; 
  curr_loc text; 
  staff_pos text; 
  t time;
BEGIN
  t := CAST(NEW.saletime AS time);

  -- Find the current location
  SELECT d.dlocation 
    INTO curr_loc
    FROM staff st 
    JOIN dept d ON d.deptno = st.deptno
  WHERE st.staffno = NEW.servedby;

  --Find the recent sale by customer in last 5 minutes
  SELECT d.dlocation 
    INTO prev_loc
    FROM sales s
    JOIN staff st ON st.staffno = s.servedby
    JOIN dept  d ON d.deptno  = st.deptno
  WHERE s.customerno = NEW.customerno
    AND s.saletime   < NEW.saletime
    AND s.saletime   >= NEW.saletime - INTERVAL '5 minutes'
  ORDER BY s.saletime DESC
  LIMIT 1;

  --Check if the previous location(within 5mins) and the current location
  IF prev_loc IS NOT NULL AND curr_loc IS DISTINCT FROM prev_loc THEN
    RAISE EXCEPTION 
      'Purchase denied: customer % had a purchase at a different location within the last 5 minutes.',
      NEW.customerno;
  END IF;

  --No sales allow outside opeining hours except Manager
  SELECT position INTO staff_pos
    FROM staff 
    WHERE staffno = NEW.servedby;
  IF (t < TIME '06:00:00' OR t >= TIME '21:00:00') 
    AND (staff_pos IS NULL OR staff_pos NOT ILIKE '%Manager%') THEN
    RAISE EXCEPTION 'Purchase denied: sales allowed only between 06:00 and 21:00 unless by a Manager.';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER TIME_CHECK
BEFORE INSERT ON sales
FOR EACH ROW
EXECUTE FUNCTION UDF_TIME_CHECK();