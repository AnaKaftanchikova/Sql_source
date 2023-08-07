DECLARE
v_table_name  varchar2(1000) := 'CBD.UVD_DECL';

fieldname1  varchar2(1000) := 'VES_NETTO';
fieldname2  varchar2(1000) := 'VES_BR';

SQLBLOCK varchar2(2000);

cursor c1 is SELECT dt_id,ves_netto,ves_br FROM CBD.UVD_DECL;
type t1 is table of c1%rowtype; 
curtype t1;

BEGIN
 
    EXECUTE IMMEDIATE 'UPDATE '|| v_table_name || ' SET '|| fieldname1 || '=NULL,' || fieldname2 || '=NULL';
    COMMIT;

    dbms_output.put_line('1: UPDATE IN NULL');

    BEGIN
        EXECUTE IMMEDIATE 'ALTER TABLE '|| v_table_name || ' MODIFY (VES_NETTO NUMBER(13,6),VES_BR NUMBER(13,6))';        
        dbms_output.put_line('2: ALTER TABLE');
        
        EXCEPTION WHEN OTHERS THEN                 
        dbms_output.put_line('Error Code: '||SQLCODE || ';' || 'Error Message: '||sqlerrm);
    END;

    open c1; 
    fetch c1 bulk collect into curtype;  
    for i in 1..curtype.count loop       
    
        SQLBLOCK:= 'UPDATE '|| v_table_name || ' SET '|| fieldname1 || '=:1,' || fieldname2 || '=:2' ||' WHERE DT_ID =:3';     
        EXECUTE IMMEDIATE SQLBLOCK USING curtype(i).ves_netto, curtype(i).ves_br, curtype(i).dt_id;

    END LOOP;

    COMMIT;
    dbms_output.put_line('3: UPDATE IN LOOP');    

    EXCEPTION WHEN OTHERS THEN                 
        dbms_output.put_line('Error Code: '||SQLCODE || ';' || 'Error Message: '||sqlerrm);

END;