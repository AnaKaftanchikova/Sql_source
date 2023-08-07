SELECT XMLROOT (
          XMLELEMENT (
             "soap:Envelope",
             XMLAttributes (
                'http://schemas.xmlsoap.org/soap/envelope/' AS "xmlns:soap"),
             XMLELEMENT (
                "soap:Header",
                XMLELEMENT ("DocumentID", :DocumentId),
                XMLELEMENT ("Sender", :Sender),
                XMLELEMENT ("TKSG", :DocumentModeId),
                XMLELEMENT ("Owner", 'Местоположение'),
                XMLELEMENT ("Receiver", :Receiver),
                XMLELEMENT ("DateOut", :DateOutT)),
             XMLELEMENT (
                "soap:Body",
                XMLELEMENT (
                   "Inf:Information",
                   XMLAttributes (
                      'http://www.w3.org/2001/XMLSchema-instance' AS "xmlns:xsi",
                      'urn:customs.interchange:Information:1.0' AS "xmlns:Inf",
                      'urn:customs:CommonAggregateTypes:1.0.0' AS "xmlns:cat"),
                   XMLELEMENT ("cat:DocumentID", :DocumentId),
                   XMLELEMENT ("Inf:ConsignmentIdentifier",
                               '112' || I.NOM_REG),
                   XMLELEMENT (
                      "Inf:TransportInfo",
                      XMLELEMENT ("Inf:TransportModeCode", ' '),
                      XMLELEMENT ("Inf:BorderTransportModeCode",
                                  I.G21_25TRANSPORTMODECODE),
                      XMLELEMENT (
                         "Inf:TransportNumber",
                         (SELECT G21_25TRANSPORTREGNUMBER
                            FROM DT_BORDERTRANSPORTMEANS BOR
                           WHERE BOR.DT_ID = I.DT_ID AND ROWNUM = 1)),
                      XMLELEMENT (
                         "Inf:ContainerNumber",
                         (SELECT XMLAGG (
                                    XMLELEMENT (
                                       "cat:ContainerIdentificator",
                                       CON.G313CONTAINERIDENTIFICATOR))
                            FROM DT_CONTAINERDETAILS CON, AZ_GOODSINFO G
                           WHERE     CON.DT_ID = G.DT_ID
                                 AND G.G32GOODSNUMERIC = CON.G32GOODSNUMERIC
                                 AND G.DT_ID = I.DT_ID),
                         XMLELEMENT ("cat:Indicator",
                                     I.G19CONTAINERINDICATOR)),
                      XMLELEMENT (
                         "Inf:DepartTransport",
                         XMLELEMENT ("Inf:TransportIdentifier",
                                     I.G18_26TRANSPORTMODECODE),
                         XMLELEMENT ("Inf:TransportMeansNationalityCode",
                                     I.G18_26TRANSPORTNATIONALITYCODE)),
                      (SELECT XMLAGG (
                                 XMLELEMENT (
                                    "Inf:GoodsInfo",
                                    XMLFOREST (
                                       G.G37MAINCUSTOMSMODECODE "Inf:ProcedureCode",
                                       ' ' "Inf:TotalPackageQuantity",
                                       ' ' "Inf:TotalGoodsQuantity",
                                       G.G32GOODSNUMERIC "Inf:GoodsNumeric",
                                       G.G331GOODSTNVEDCODE "Inf:GoodsTNVEDCode"),
                                    (SELECT XMLAGG (
                                               XMLELEMENT (
                                                  "Inf:GoodsDescription",
                                                  GOODSDESCRIPTION))
                                       FROM DT_GOODSDESCRIPTION D
                                      WHERE D.DT_ID = G.DT_ID
                                            AND G.G32GOODSNUMERIC =
                                                   D.G32GOODSNUMERIC
                                            AND D.LINE_ID = 1),
                                    XMLFOREST (
                                       ' ' "Inf:PackQuantity",
                                       ' ' "Inf:PackCode",
                                       G.G35GROSSWEIGHTQUANTITY "Inf:GrossWeight",
                                       G.G38NETWEIGHTQUANTITY "Inf:NetWeight",
                                       REPLACE (G.G42INVOICEDCOST, ',', '.') "Inf:AmountInvoice",
                                       (SELECT DISTINCT CODE
                                          FROM CTRL_NSI_VALUTA
                                         WHERE CODE_ABR =
                                                  (SELECT DISTINCT
                                                          CURRENCYCODE
                                                     FROM AZ_GOODSINFO INF
                                                    WHERE INF.DT_ID = G.DT_ID
                                                          AND INF.
                                                               G32GOODSNUMERIC =
                                                                 G.
                                                                  G32GOODSNUMERIC
                                                          AND INF.EVENT_ID =
                                                                 I.EVENT_ID)
                                               AND SYSDATE BETWEEN D_ON
                                                               AND D_OFF) "Inf:Currency",
                                       I.G15ADISPATCHCOUNTRYCODE "Inf:CountryDispatchCode",
                                       G.G34ORIGINCOUNTRYCODE "Inf:OriginCountryCode",
                                       XMLELEMENT (
                                          "Inf:StatisticalCost",
                                          REPLACE (G.G46STATISTICALCOST,
                                                   ',',
                                                   '.')),
                                       XMLELEMENT ("Inf:DateRelease",
                                                   I.DT_DATE),
                                       I.G17ADESTINATIONCOUNTRYCODE "Inf:CountryDestinationCode",
                                       I.G111TRADECOUNTRYCODE "Inf:CountryTradeCode",
                                       I.NOM_REG "Inf:DeclNum"),
                                    (SELECT XMLELEMENT (
                                               "Inf:SupplementaryQuantity",
                                               XMLFOREST (
                                                  G.G41GOODSQUANTITY "cat:GoodsQuantity",
                                                  G41MEASUREUNITQUALIFIERCODE "cat:MeasureUnitQualifierCode"))
                                       FROM AZ_GOODSINFO F
                                      WHERE F.DT_ID = G.DT_ID
                                            AND F.G32GOODSNUMERIC =
                                                   G.G32GOODSNUMERIC
                                            AND (G.G41GOODSQUANTITY
                                                    IS NOT NULL
                                                 OR G41MEASUREUNITQUALIFIERCODE
                                                       IS NOT NULL))))
                        FROM DT_ESADOUT_CUGOODS G
                        WHERE G.DT_ID = I.DT_ID),
                      XMLELEMENT (
                         "Inf:PersonInfo",
                         XMLELEMENT (
                            "Inf:Consignor",
                            XMLELEMENT ("Inf:OrganizationName", G02SHORTNAME),
                            XMLELEMENT ("Inf:Address", G02ADDRESS)),
                         XMLELEMENT (
                            "Inf:Consignee",
                            XMLELEMENT (
                               "Inf:OrganizationName",
                               (SELECT    H.G02COUNTRYCODE
                                       || H.G02CITY
                                       || H.G02STREETHOUSE
                                       || H.G02BUILDINGNUMBER
                                  FROM DT_ESADOUT_CU H
                                 WHERE H.DT_ID = I.DT_ID)),
                            XMLELEMENT (
                               "Inf:Address",
                               (SELECT    H.G08COUNTRYCODE
                                       || H.G08CITY
                                       || H.G08STREETHOUSE
                                       || H.G08BUILDINGNUMBER
                                  FROM DT_ESADOUT_CU H
                                 WHERE H.DT_ID = I.DT_ID)))),
                      XMLELEMENT (
                         "Inf:DocumentInfo",
                         XMLFOREST (
                            I.G20DELIVERYPLACE "Inf:DeliveryPlace",
                            I.G20DELIVERYTERMSSTRINGCODE "Inf:DeliveryTermsStringCode",
                            ' ' "Inf:ForeignTradeContractNumber",
                            ' ' "Inf:ForeignTradeContractDate",
                            ' ' "Inf:InvoiceNumber",
                            REPLACE (I.G222TOTALINVOICEAMOUNT, ',', '.') "Inf:TotalAmount",
                            (SELECT CODE
                               FROM CTRL_NSI_VALUTA
                              WHERE CODE_ABR = I.G222TOTALINVOICECURRENCYCODE
                                    AND SYSDATE BETWEEN D_ON AND D_OFF
                                    AND I.G222TOTALINVOICECURRENCYCODE
                                           IS NOT NULL) "Inf:CurrencyInvoice")))))),
          VERSION '1.0" encoding="UTF-8')
  FROM AZ_DTINFO I
 WHERE I.EVENT_ID = :event_id;