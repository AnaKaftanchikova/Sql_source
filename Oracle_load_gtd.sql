CREATE OR REPLACE PACKAGE BODY CBD.SOTI_Gtd
  AS
  --
  -- Набор символов, не несущих самостоятельного смысла
  --
  vBlank_Chars VARCHAR2(4) := ' ' || CHR(8) || CHR(10) || CHR(13);
  
  vFlag INTEGER(1) := 0;
  ------------------------------------------------------------------
  --
  -- По идентификатору ГТД pGtd_Id определяется соответствующая ей
  -- бумажная копия. Если успешно, то возвращается ее RowId в
  -- таблице Hard_Copies_All, иначе NULL
  --
  FUNCTION Find_HCopy(pGtd_Id INTEGER)
    RETURN Hard_Copies_All.HCopy_Id % TYPE
    IS
      vGA       Hard_Copies_All.NOM_RAZR % TYPE;
      vGType_Id Last_Events_All.GType_Id % TYPE;
      vG013     Last_Events_All.G013 % TYPE;
      vRes      Hard_Copies_All.HCopy_Id % TYPE;
    BEGIN
      --
      -- Находим GA и тип ГТД
      --
      SELECT Cleared_NOM_RAZR,
             GType_Id,
             G013
        INTO vGA,
             vGType_Id,
             vG013
        FROM Last_Events_All
        WHERE DT_ID = pGtd_Id;
      --
      -- Пытаемся найти БК
      --
      BEGIN
        SELECT HCopy_Id
          INTO vRes
          FROM Hard_Copies_All
          WHERE NOM_RAZR = vGA
            AND GType_Id = vGType_Id
            AND (
            HC_Type = SOTI_Const.HCT_Undefined
            OR (
            HC_Type = SOTI_Const.HCT_PS_Export
            AND vG013 = SOTI_Const.PS_Export
            )
            OR (
            HC_Type = SOTI_Const.HCT_PS_Import
            AND vG013 = SOTI_Const.PS_Import
            )
            );
        RETURN vRes;
      EXCEPTION
        WHEN No_Data_Found THEN RETURN NULL;
      END;
    END;
  ------------------------------------------------------------------
  PROCEDURE Modify_HC_Status(pGtd_Id     INTEGER,
                             pNew_Status INTEGER)
    IS
      vHCopy_Id        Hard_Copies_All.HCopy_Id % TYPE;
      vHC_Register_Id  Hard_Copies_All.HC_Register_Id % TYPE;
      vPTO_Code        Hard_Copies_All.NOM_RAZR % TYPE;
      vGtd_Nomer       Hard_Copies_All.NOM_RAZR % TYPE;
      vHC_Type         Hard_Copies_All.HC_Type % TYPE;
      vPermission_Type Hard_Copies_All.Permission_Type % TYPE;
      vGType_Id        Hard_Copies_All.GType_Id % TYPE;
      vGtd_Date        Hard_Copies_All.DT_Date % TYPE;
      vGD1             Hard_Copies_All.DATE_RAZR % TYPE;
      vIn_Date         Hard_Copies_All.In_Date % TYPE;
      vEnter_Date      Hard_Copies_All.Control_Date % TYPE;
    BEGIN
      vHCopy_Id := Find_HCopy(pGtd_Id);
      IF vHCopy_Id IS NULL
      THEN
        RETURN;
      END IF;
      --
      -- Вычитываем параметры БК
      --
      SELECT HC_Register_Id,
             SUBSTR(NOM_RAZR, 1, 5),
             SUBSTR(NOM_RAZR, 9),
             HC_Type,
             Permission_Type,
             GType_Id,
             DT_Date,
             DATE_RAZR,
             In_Date,
             Control_Date
        INTO vHC_Register_Id,
             vPTO_Code,
             vGtd_Nomer,
             vHC_Type,
             vPermission_Type,
             vGType_Id,
             vGtd_Date,
             vGD1,
             vIn_Date,
             vEnter_Date
        FROM Hard_Copies_All
        WHERE HCopy_Id = vHCopy_Id;
      --
      -- Обновляем
      --
      SOTI_HCopy.Modify_HCopy(vHCopy_Id, vPTO_Code, vGtd_Nomer, vHC_Type, vGType_Id, TRUNC(vGtd_Date, 'YEAR'), vGD1, vIn_Date, vEnter_Date, pNew_Status, vPermission_Type, vHC_Register_Id);
    END;
  ------------------------------------------------------------------
  --
  -- Определение Gtd_Date исходя из актуального состояния декларации
  --
  FUNCTION Derive_Gtd_Date(pGtd_Id INTEGER)
    RETURN DATE
    IS
      vGtd_Date DATE;
    BEGIN
      --
      -- На теперешний момент Gtd_Date идентично дате оформления
      --
      SELECT DATE_RAZR
        INTO vGtd_Date
        FROM Last_Events_All
        WHERE DT_Id = pGtd_Id;
      RETURN vGtd_Date;
    END;
  ------------------------------------------------------------------
  --
  -- Процедура гарантирует, что значение служебного поля Gtd_Date
  --   во всей иерархии объектов соответствует содержимому декларации
  --
  PROCEDURE Verify_Gtd_Date(pGtd_Id INTEGER)
    IS
      vOld_Gtd_Date DATE;
      vNew_Gtd_Date DATE;
    BEGIN
      SELECT DT_Date
        INTO vOld_Gtd_Date
        FROM SP_Gtds_All
        WHERE DT_ID = pGtd_Id;
      vNew_Gtd_Date := Derive_Gtd_Date(pGtd_Id);
      IF vOld_Gtd_Date IS NULL
        OR vNew_Gtd_Date IS NULL
      THEN
        Raise_Application_Error(SOTI_Exceptions.App_Error, SOTI_Exceptions.App_Error_Text);
      END IF;
      --
      IF vNew_Gtd_Date <> vOld_Gtd_Date
      THEN
        SOTI_Update_Gtd_Date.Do_It(pGtd_Id, vNew_Gtd_Date);
      END IF;
    END;
  ------------------------------------------------------------------
  FUNCTION Derive_Status_Group(pGtd_Status INTEGER)
    RETURN INTEGER
    IS
      vStatus_Grp Gtd_Statuses.Status_Grp % TYPE;
    BEGIN
      SELECT Status_Grp
        INTO vStatus_Grp
        FROM GTD_Statuses
        WHERE DT_Status = pGtd_Status;
      RETURN vStatus_Grp;
    END;
  ------------------------------------------------------------------
  PROCEDURE Check_Lock_Mode(pGtd_Id      INTEGER,
                            pFor_Edit    CHAR,
                            pFor_Clarify CHAR,
                            pFor_Revise  CHAR)
    IS
      vIs_Locked       CHAR;
      vCur_For_Edit    CHAR;
      vCur_For_Clarify CHAR;
      vCur_For_Revise  CHAR;
    BEGIN
      vIs_Locked := SOTI_Lock.Get_Lock_Mode(pGtd_Id,vCur_For_Edit, vCur_For_Clarify, vCur_For_Revise);
      IF vIs_Locked = SOTI_Const.cNo
      THEN
        SOTI_Lock.Lock_Gtd(pGtd_Id, pFor_Edit, pFor_Clarify, pFor_Revise);
      ELSE
        IF vCur_For_Edit <> pFor_Edit
          OR vCur_For_Clarify <> pFor_Clarify
          OR vCur_For_Revise <> pFor_Revise
        THEN
          SOTI_Lock.Modify_Lock_Mode(pGtd_Id, pFor_Edit, pFor_Clarify, pFor_Revise);
        END IF;
      END IF;
    END;
  ------------------------------------------------------------------
  FUNCTION is_Backup_Exists(pEvent_Id SOTI_Types.T_Id)
    RETURN INTEGER
    IS
    BEGIN
      RETURN Cfg_Execute.Exec_Is_Backup_Exists(SOTI_Util.Gtd_To_DStructure(SOTI_Util.Event_To_Gtd(pEvent_Id)), pEvent_Id);
    END;
  ------------------------------------------------------------------
  FUNCTION Is_Event_Undone(pEvent_Id SOTI_Types.T_Id)
    RETURN INTEGER
    IS
      vGtd_Id        INTEGER;
      vLast_Event_Id INTEGER;
      vTemp_Id       INTEGER;
      vEvent_Type    INTEGER;
      --
      FUNCTION Is_Predecessor_Or_Itself(pUndone_Event_Id SOTI_Types.T_Id)
        RETURN INTEGER
        IS
          vCnt INTEGER;
        BEGIN
          --
          -- Функция проверяет, является ли событие pUndone_Event_Id
          --   предшественником pEvent_Id
          --
          SELECT COUNT(*)
            INTO vCnt
            FROM Event_Log_All
            WHERE Event_Id = pUndone_Event_Id
          START WITH Event_Id = pEvent_Id
          CONNECT BY Event_Id = PRIOR Prev_Event_Id;
          IF vCnt <> 1
          THEN
            RETURN SOTI_Const.No;
          END IF;
          RETURN SOTI_Const.Yes;
        END;
    BEGIN
      --
      -- Проверяем привилегии
      --
      SOTI_Auth.Check_Auth_On_Event(pEvent_Id);
      --
      vGtd_Id := SOTI_Util.Event_To_Gtd(pEvent_Id);
      SELECT Event_Id
        INTO vLast_Event_Id
        FROM Event_Log_All
      START WITH Event_Id = pEvent_Id
      CONNECT BY PRIOR Event_Id = Prev_Event_Id
        MINUS
      SELECT Prev_Event_Id
        FROM Event_Log_All
        WHERE DT_Id = vGtd_Id;
      --
      -- Проходим по событиям начиная с последнего,
      --   ищем события отмены и проверяем,
      --   не отменяют ли они pEvent_Id
      --
      vTemp_Id := vLast_Event_Id;
      LOOP
        IF vTemp_Id = pEvent_Id
        THEN
          RETURN SOTI_Const.No;
        END IF;
        SELECT Event_Type
          INTO vEvent_Type
          FROM Event_Log_All
          WHERE Event_Id = vTemp_Id;
        IF vEvent_Type = SOTI_Const.Ev_Undo
        THEN
          SELECT Undone_Event_Id
            INTO vTemp_Id
            FROM Event_Log_All
            WHERE Event_Id = vTemp_Id;
          IF Is_Predecessor_Or_Itself(vTemp_Id) = SOTI_Const.Yes
          THEN
            --
            -- Текущее событие отката отменяет pEvent_Id
            --
            RETURN SOTI_Const.Yes;
          END IF;
        END IF;
        SELECT Prev_Event_Id
          INTO vTemp_Id
          FROM Event_Log_All
          WHERE Event_Id = vTemp_Id;
        IF vTemp_Id IS NULL
        THEN
          --
          -- Ошибка в БД - до начала дойти никак не можем,
          --   должны упереться в pEvent_Id
          --
          Raise_Application_Error(SOTI_Exceptions.App_Error, SOTI_Exceptions.App_Error_Text);
        END IF;
      END LOOP;
    END;
  ------------------------------------------------------------------
  FUNCTION Can_Undo(pEvent_Id SOTI_Types.T_Id)
    RETURN INTEGER
    IS
      vPrev_Event_Id INTEGER;
    BEGIN
      --
      -- Отменить событие фиктивного редактирования нельзя
      -- Проверяется автоматически, так как
      --   для него нет резервной копии
      --
      -- Событие можно отменить, если:
      -- 1. Отменяется не первое событие (не поступление)
      -- 2. Событие не отменено
      -- 3. Есть резервная копия
      -- 4. Событие выполнено в локальной БД, а не реплицировано из удаленной
      --
      -- Проверка на первое событие (поступление)
      --
      SELECT Prev_Event_Id
        INTO vPrev_Event_Id
        FROM Event_Log_All
        WHERE Event_Id = pEvent_Id;
      IF vPrev_Event_Id IS NULL
      THEN
        RETURN SOTI_Const.No;
      END IF;
      --
      -- Проверка, отменено событие или нет
      --
      IF Is_Event_Undone(pEvent_Id) = SOTI_Const.Yes
      THEN     
        RETURN SOTI_Const.No;
      END IF;            
      --
      -- Проверка наличия резервной копии
      --
      IF Event_To_BkData_Id(pEvent_Id) = 0
      THEN   
        RETURN SOTI_Const.No;
      END IF;
      --
      -- Проверка на то, что событие выполнено в локальной БД
      --
      IF SOTI_Util.Is_Event_Local(pEvent_Id) <> SOTI_Const.Yes
      THEN      
        RETURN SOTI_Const.No;
      END IF;
      --
      RETURN SOTI_Const.Yes;
    END;
  ------------------------------------------------------------------
  --
  -- После события добавляем обработку ТД как спец.
  --
  PROCEDURE Do_Spec_Support(pGtd_Id     INTEGER,
                            pEvent_Type INTEGER)
    IS
    BEGIN
      IF SOTI_Spec.Is_Spec_Supported = SOTI_Const.cYes
      THEN
        Check_Lock_Mode(pGtd_Id, SOTI_Const.cNo, SOTI_Const.cNo, SOTI_Const.cYes);
        / Информируем спец. подсистему, что ТД изменился /
        SOTI_Spec.Register_As_Modified(pGtd_Id, pEvent_Type);
      END IF;
    END;
  ------------------------------------------------------------------
  FUNCTION Start_Event(pEvent_Type     SOTI_Types.T_Id,
                       pGtd_Id         SOTI_Types.T_Id,
                       pStatus         INTEGER,
                       pLetter_Id      SOTI_Types.T_Id,
                       pComputer_Name  VARCHAR2,
                       pNet_Address    VARCHAR2,
                       pEvent_Comments VARCHAR2 DEFAULT NULL)
    RETURN SOTI_Types.T_Id
    IS
    BEGIN
      RETURN SOTI_Bd.Start_Event(pEvent_Type, pGtd_Id, pStatus, pLetter_Id,
      pComputer_Name, pNet_Address, pEvent_Comments);
    END;
  ------------------------------------------------------------------
  FUNCTION Open_for_Edit(pGtd_Id          SOTI_Types.T_Id,
                         pLetter_Id       SOTI_Types.T_Id,
                         pComputer_Name   VARCHAR2,
                         pNet_Address     VARCHAR2,
                         pEdit_Type       INTEGER,
                         pEvent_Initiator VARCHAR2,
                         pEvent_Comments  VARCHAR2)
    RETURN SOTI_Types.T_Id
    IS
      vEvent_Id      INTEGER;
      vPrev_Event_Id INTEGER;
    BEGIN
      --
      -- Проверяем параметр pEvent_Initiator
      --
      BTS_UTIL.LOG('Open_for_Edit: ' || pGtd_Id || ':' || pEdit_Type);
      IF (
        pEdit_Type IS NULL
        OR pEdit_Type NOT IN (SOTI_Const.Ev_Edit, SOTI_Const.Ev_Internal_Edit)
        )
        OR (
        pEvent_Initiator IS NOT NULL
        AND pEvent_Initiator NOT IN (SOTI_Const.EVI_Customs, SOTI_Const.EVI_Declarant)
        )
      THEN
        Raise_Application_Error(SOTI_Exceptions.Invalid_Parameter, SOTI_Exceptions.Invalid_Parameter_Text);
      END IF;
      --
      -- ЭК должна быть локальной
      --
      SOTI_Util.Check_Gtd_Local(pGtd_Id);
      --
      -- Права будут проверены при получении блока
      --
      Check_Lock_Mode(pGtd_Id, SOTI_Const.cYes, SOTI_Const.cYes, SOTI_Const.cNo);
      --
      vPrev_Event_Id := SOTI_Util.Gtd_To_Event(pGtd_Id);
      vEvent_Id := Start_Event(pEdit_Type, pGtd_Id, SOTI_Const.Status_Incomplete_Edit,
      pLetter_Id, pComputer_Name, pNet_Address, pEvent_Comments);
      --
      -- Устанавливаем Event_Initiator
      --
      Set_Event_Initiator(vEvent_Id, pEvent_Initiator);
      --
      -- Копируем ошибки, которые, пока ГТД не отредактирована, не исправлены
      --
      -- NEW !!!!!!
      --
      --  INSERT INTO SP_Errors_All(SP_Error_Id, Event_Id, CDoc_Type_Id, GType_Id,
      --      PTO_Code, Err_Code, PErr_Code, G32, Err_Params, Is_Real)
      --    SELECT Seq_SP_Error_Id.NextVal, vEvent_Id, CDoc_Type_Id, GType_Id,
      --      PTO_Code, Err_Code, PErr_Code, G32, Err_Params, Is_Real
      --    FROM SP_Errors_All
      --    WHERE Event_Id = vPrev_Event_Id
      --      AND Is_Real <> SOTI_Const.cNo;
      --
      RETURN vEvent_Id;
    END;
  ------------------------------------------------------------------
  FUNCTION Open_for_Clarify(pGtd_Id        SOTI_Types.T_Id,
                            pLetter_Id     SOTI_Types.T_Id,
                            pComputer_Name VARCHAR2,
                            pNet_Address   VARCHAR2)
    RETURN SOTI_Types.T_Id
    IS
      vEvent_Id      INTEGER;
      vPrev_Event_Id INTEGER;
    BEGIN
      --
      -- По новой модели событие выяснения уходит
      --
      Raise_Application_Error(SOTI_Exceptions.App_Error, SOTI_Exceptions.App_Error_Text);
      --
      -- Права будут проверены при получении блока
      -- Блок предполагает редактирование ТД для изменения Gtd_Status в
      --   процедуре Start_Event. Сразу после нее возможность редактирования снимается
      --
      Check_Lock_Mode(pGtd_Id, SOTI_Const.cYes, SOTI_Const.cYes, SOTI_Const.cNo);
      --
      -- ЭК должна быть локальной
      --
      SOTI_Util.Check_Gtd_Local(pGtd_Id);
      --
      vPrev_Event_Id := SOTI_Util.Gtd_To_Event(pGtd_Id);
      vEvent_Id := Start_Event(SOTI_Const.Ev_Clarify, pGtd_Id, SOTI_Const.Status_Incomplete_Edit,
      pLetter_Id, pComputer_Name, pNet_Address);
      Check_Lock_Mode(pGtd_Id, SOTI_Const.cNo, SOTI_Const.cYes, SOTI_Const.cNo);
      --
      -- Копируем ошибки, которые и будут разбираться
      --
      -- NEW !!!!!!
      --
      --  INSERT INTO SP_Errors_All(SP_Error_Id, Event_Id, CDoc_Type_Id, GType_Id,
      --      PTO_Code, Err_Code, PErr_Code, G32, Err_Params, Is_Real)
      --    SELECT Seq_SP_Error_Id.NextVal, vEvent_Id, CDoc_Type_Id, GType_Id,
      --      PTO_Code, Err_Code, PErr_Code, G32, Err_Params, Is_Real
      --    FROM SP_Errors_All
      --    WHERE Event_Id = vPrev_Event_Id
      --      AND Is_Real <> SOTI_Const.cNo;
      --
      RETURN vEvent_Id;
    END;
  ------------------------------------------------------------------
  --
  -- Интерактивная регистрация ошибок выполняется через регистрацию события контроля
  --
  -- NEW !!!!!!
  --
  FUNCTION Open_for_Control(pGtd_Id        SOTI_Types.T_Id,
                            pLetter_Id     SOTI_Types.T_Id,
                            pComputer_Name VARCHAR2,
                            pNet_Address   VARCHAR2)
    RETURN SOTI_Types.T_Id
    IS
      vEvent_Id      INTEGER;
      vPrev_Event_Id INTEGER;
      vCur_Status    INTEGER;
    BEGIN
      --
      -- Права будут проверены при получении блока
      -- Блок предполагает редактирование ТД для изменения Gtd_Status в
      --   процедуре Start_Event. Сразу после нее возможность редактирования снимается
      --
      Check_Lock_Mode(pGtd_Id, SOTI_Const.cYes, SOTI_Const.cYes, SOTI_Const.cNo);
      --
      -- ЭК должна быть локальной
      --
      SOTI_Util.Check_Gtd_Local(pGtd_Id);
      --
      vPrev_Event_Id := SOTI_Util.Gtd_To_Event(pGtd_Id);
      SELECT DT_Status
        INTO vCur_Status
        FROM Last_Events_All
        WHERE DT_Id = pGtd_Id;
      vEvent_Id := Start_Event(SOTI_Const.Ev_Control, pGtd_Id, vCur_Status,
      pLetter_Id, pComputer_Name, pNet_Address);
      Check_Lock_Mode(pGtd_Id, SOTI_Const.cNo, SOTI_Const.cYes, SOTI_Const.cNo);
      --
      RETURN vEvent_Id;
    END;
  ------------------------------------------------------------------
  --
  -- Очищение содержимого ГТД перед сохранением
  --   отредактированной версии
  --
  PROCEDURE Clear_Before_Save(pGtd_Id INTEGER)
    IS
    BEGIN
      --
      -- Проверка открытия ГТД по Open_for_Edit
      --   т.е. проверка блока
      --
      IF SOTI_Lock.is_Edited_By_Me(pGtd_Id) = SOTI_Const.No
      THEN
        Raise_Application_Error(SOTI_Exceptions.Gtd_Not_Locked, SOTI_Exceptions.Gtd_Not_Locked_Text);
      END IF;
      --
      -- Очищение
      --
      Cfg_Execute.Exec_Clear_Bd(SOTI_Util.Gtd_To_DStructure(pGtd_Id), pGtd_Id);
    END;
  ------------------------------------------------------------------
  --
  -- Закрытие ГТД после изменеия,
  --   т.е. открытия Open_for_Edit или Open_for_Clarify
  --
  PROCEDURE Close(pEvent_Id SOTI_Types.T_Id,
                  pStatus   INTEGER,
                  pCancel   INTEGER)
    IS
      --  vErr_Cnt INTEGER;
      --  vUnknown_Cnt INTEGER;
      vGtd_Id INTEGER;
    BEGIN
      --
      -- Отмена события
      -- Выполняем ее до проверки того, что декларация действительно открыта,
      --   т.к. она реализуется обыкновенным ROLLBACK`ом. При отмене редактирования
      --   группы ТД Close для первого ТД фактически закроет и все остальные ТД группы.
      --   Тогда последующие вызовы Close для остальных ТД группы не будет вызывать
      --   ошибки.
      --
      IF pCancel = SOTI_Const.Yes
      THEN
        ROLLBACK;
        RETURN;
      END IF;
      --
      -- Проверка открытия ГТД по Open_for_Edit или Open_for_Clarify
      --   т.е. проверка блока
      --
      IF
        (
        SOTI_Lock.is_Edited_By_Me(SOTI_Util.Event_To_Gtd(pEvent_Id)) = SOTI_Const.No
        AND SOTI_Lock.is_Clarified_By_Me(SOTI_Util.Event_To_Gtd(pEvent_Id)) = SOTI_Const.No
        )
        OR SOTI_Util.Is_Event_Last(pEvent_Id) <> SOTI_Const.Yes
        OR SOTI_Util.Is_Event_Local(pEvent_Id) <> SOTI_Const.Yes
      THEN
        Raise_Application_Error(SOTI_Exceptions.Gtd_Not_Locked, SOTI_Exceptions.Gtd_Not_Locked_Text);
      END IF;
      --
      -- Проверка параметра pStatus
      --
      DECLARE
        vEvent_Type   INTEGER;
        vPrior_Status INTEGER;
      BEGIN
        /* В случае технической корректировки статус должен быть таким же,
           как и до корректировки */
        SELECT /*+ ORDERED INDEX(Ev) USE_NL(Ev Prev_Ev) INDEX(Prev_Ev) */
        Ev.Event_Type,
        Prev_Ev.DT_Status
          INTO vEvent_Type,
               vPrior_Status
          FROM Event_Log_All Ev,
               Event_Log_All Prev_Ev
          WHERE Ev.Event_Id = pEvent_Id
            AND Ev.Prev_Event_Id = Prev_Ev.Event_Id;
        IF (
          vEvent_Type = SOTI_Const.Ev_Internal_Edit
          AND vPrior_Status <> NVL(pStatus, -1)
          )
          OR (
          vEvent_Type = SOTI_Const.Ev_Edit
          AND NVL(pStatus, -1) NOT IN (
          SOTI_Const.Status_Active, SOTI_Const.Status_Wrong,
          SOTI_Const.Status_Clarification, SOTI_Const.Status_Refuse, SOTI_Const.Status_Recall)
          )
        THEN
          Raise_Application_Error(SOTI_Exceptions.Invalid_Close_Status, SOTI_Exceptions.Invalid_Close_Status_Text);
        END IF;
      END;
      --
      -- Проверяем соответствие pStatus зарегистрированным ошибкам
      --
      -- NEW !!!!!!
      --
      --  SELECT
      --      Count(DECODE(Is_Real, SOTI_Const.cYes, 1, NULL)),
      --      Count(DECODE(Is_Real, SOTI_Const.cUnknown, 1, NULL))
      --    INTO vErr_Cnt, vUnknown_Cnt
      --    FROM SP_Errors_All
      --    WHERE Event_Id = pEvent_Id;
      --  IF pStatus = SOTI_Const.Status_Wrong
      --    AND vErr_Cnt = 0 THEN
      --    Raise_Application_Error(SOTI_Exceptions.Invalid_ErrStatus_Advised,
      --      SOTI_Exceptions.Invalid_ErrStatus_Advised_Text);
      --  END IF;
      --  IF pStatus = SOTI_Const.Status_Active
      --    AND (vErr_Cnt + vUnknown_Cnt) > 0 THEN
      --    Raise_Application_Error(SOTI_Exceptions.Invalid_OK_Status_Advised,
      --      SOTI_Exceptions.Invalid_OK_Status_Advised_Text);
      --  END IF;
      --
      -- Определяем Gtd_Id
      --
      SELECT DT_Id
        INTO vGtd_Id
        FROM Event_Log_All
        WHERE Event_Id = pEvent_Id;
      --
      -- Обновление статуса события
      --
      UPDATE Event_Log_All
        SET DT_Status = pStatus
        WHERE Event_Id = pEvent_Id;
      --
      -- Обновляем текущий статус ТД, включая Last_Events_XXX_All
      --
      SOTI_Update_Gtd_Status.Do_It(vGtd_Id, pStatus, Derive_Status_Group(pStatus), SOTI_Const.cYes);
      --
      -- Обрабатываем изменения Gtd_Date
      --
      Verify_Gtd_Date(vGtd_Id);
      --
      -- Обновляем иерархию
      --
      IF SOTI_Gtd_Hierarchy.Is_Generated(vGtd_Id)
      THEN
        SOTI_Gtd_Hierarchy.Verify_Hierarchy(vGtd_Id, FALSE);
      END IF;
      --
      -- Проверяем ТД на спец.
      --
      DECLARE
        vEvent_Type INTEGER;
      BEGIN
        SELECT Event_Type
          INTO vEvent_Type
          FROM Event_Log_All
          WHERE Event_Id = pEvent_Id;
        Do_Spec_Support(vGtd_Id, vEvent_Type);
      END;
      --
      -- Снимаем возможность редактирования ТД
      --
      Check_Lock_Mode(vGtd_Id, SOTI_Const.cNo, SOTI_Const.cNo, SOTI_Const.cNo);
    END;
  ------------------------------------------------------------------
  --PROCEDURE Dummy_Edit(
  --  pGtd_Id     SOTI_Types.T_Id,
  --  pNet_Address VARCHAR2
  --) IS
  --  Dummy SOTI_Types.T_Id;
  --BEGIN
  --  -- Права будут проверены при получении блока
  --  Check_Lock_Mode(pGtd_Id, SOTI_Const.cYes, SOTI_Const.cNo);
  --  Dummy := Start_Event(SOTI_Const.Ev_DummyEdit, pGtd_Id, SOTI_Const.Status_Active,
  --    NULL, pNet_Address);
  --  Check_Lock_Mode(pGtd_Id, SOTI_Const.cNo, SOTI_Const.cNo);
  --END;
  ------------------------------------------------------------------
  PROCEDURE Cancel(   -- Аннулирование ГТД
    pDT_Id         SOTI_Types.T_Id,
    pLetter_Id     SOTI_Types.T_Id,
    pComputer_Name VARCHAR2,
    pNet_Address   VARCHAR2)
    IS
      Dummy SOTI_Types.T_Id;
    BEGIN
      --
      -- Права будут проверены при получении блока
      -- Блок предполагает редактирование ТД для изменения Gtd_Status в
      --   процедуре Start_Event. Сразу после нее возможность редактирования снимается
      --
      Check_Lock_Mode(pDT_Id, SOTI_Const.cYes, SOTI_Const.cNo, SOTI_Const.cNo);
      --
      -- ЭК должна быть локальной
      --
      SOTI_Util.Check_Gtd_Local(pDT_Id);
      --
      Dummy := Start_Event(SOTI_Const.Ev_Cancel, pDT_Id, SOTI_Const.Status_Cancelled,
      pLetter_Id, pComputer_Name, pNet_Address);
      --
      -- Поддержка спец. данных
      --
      Do_Spec_Support(pDT_Id, SOTI_Const.Ev_Cancel);
      --
      -- Меняем режим блока
      --
      Check_Lock_Mode(pDT_Id, SOTI_Const.cNo, SOTI_Const.cNo, SOTI_Const.cNo);
      --
      -- Аннулируем бумажную копию
      --
      Modify_HC_Status(pDT_Id, SOTI_Const.Status_Cancelled);
    END;
END;
/