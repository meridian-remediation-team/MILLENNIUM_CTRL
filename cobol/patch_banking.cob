      *================================================================*
      * PROGRAM:    PATCH-BANKING                                      *
      * AUTHOR:     MERIDIAN REMEDIATION TEAM                         *
      * DATE:       1999-09-14                                         *
      * PURPOSE:    Y2K PATCH FOR FINANCIAL CORE SUBROUTINES           *
      *             FIXES 2-DIGIT YEAR IN CALC-INTEREST-YR             *
      *             AND DATE-COMPARE ROUTINES                          *
      *             TARGET LIB: fincore.so (lines 2201, 4455, 4456)   *
      *================================================================*
      *
      * PATCH NOTES:
      *   Original code used PIC 99 for year storage throughout.
      *   This patch replaces all YY fields with YYYY (PIC 9999).
      *   The windowing approach (pivot year 50) was REJECTED by cole.
      *   Full 4-digit year expansion only. No shortcuts.
      *
      *   Known dependent modules that must be relinked after patch:
      *     - billrun (invoice date generation)
      *     - accrual_batch (interest accrual runner)
      *     - stmt_gen (statement generation -- quarterly)
      *
      *================================================================*

       IDENTIFICATION DIVISION.
       PROGRAM-ID. PATCH-BANKING.
       AUTHOR. MERIDIAN-OPS.
       DATE-WRITTEN. 1999-09-14.
       DATE-COMPILED.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-3090.
       OBJECT-COMPUTER. IBM-3090.

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT TRANS-FILE  ASSIGN TO TRANSIN
                              ORGANIZATION IS SEQUENTIAL.
           SELECT REPORT-FILE ASSIGN TO REPOUT
                              ORGANIZATION IS SEQUENTIAL.

       DATA DIVISION.
       FILE SECTION.

       FD  TRANS-FILE
           LABEL RECORDS ARE STANDARD
           RECORD CONTAINS 256 CHARACTERS.
       01  TRANS-RECORD.
           05  TR-ACCOUNT-ID      PIC X(12).
           05  TR-TRANS-TYPE      PIC X(4).
           05  TR-AMOUNT          PIC S9(13)V99 COMP-3.
           05  TR-DATE.
               10  TR-YEAR        PIC 9(4).          *> PATCHED: was 9(2)
               10  TR-MONTH       PIC 9(2).
               10  TR-DAY         PIC 9(2).
           05  TR-MATURITY-DATE.
               10  TR-MAT-YEAR    PIC 9(4).          *> PATCHED: was 9(2)
               10  TR-MAT-MONTH   PIC 9(2).
               10  TR-MAT-DAY     PIC 9(2).
           05  FILLER             PIC X(211).

       FD  REPORT-FILE
           LABEL RECORDS ARE STANDARD
           RECORD CONTAINS 132 CHARACTERS.
       01  REPORT-RECORD          PIC X(132).

       WORKING-STORAGE SECTION.

       01  WS-FLAGS.
           05  WS-END-OF-FILE     PIC X(1)    VALUE 'N'.
           05  WS-ERROR-FLAG      PIC X(1)    VALUE 'N'.
           05  WS-DATE-VALID      PIC X(1)    VALUE 'N'.

       01  WS-COUNTERS.
           05  WS-RECORD-COUNT    PIC 9(9)    VALUE ZEROS.
           05  WS-ERROR-COUNT     PIC 9(9)    VALUE ZEROS.
           05  WS-PATCHED-COUNT   PIC 9(9)    VALUE ZEROS.

      *----------------------------------------------------------------*
      * DATE WORK AREAS -- ALL 4-DIGIT YEAR AFTER PATCH               *
      *----------------------------------------------------------------*
       01  WS-CURRENT-DATE.
           05  WS-CURR-YEAR       PIC 9(4).
           05  WS-CURR-MONTH      PIC 9(2).
           05  WS-CURR-DAY        PIC 9(2).

       01  WS-COMPARE-DATE.
           05  WS-COMP-YEAR       PIC 9(4).
           05  WS-COMP-MONTH      PIC 9(2).
           05  WS-COMP-DAY        PIC 9(2).

       01  WS-DAYS-REMAINING      PIC S9(9)   VALUE ZEROS.
       01  WS-INTEREST-RATE       PIC S9(3)V9(6) COMP-3.
       01  WS-INTEREST-AMT        PIC S9(13)V99 COMP-3.
       01  WS-DAYS-IN-YEAR        PIC 9(4)    VALUE 365.

      *----------------------------------------------------------------*
      * ORIGINAL BROKEN FIELDS (kept for documentation only)          *
      * DO NOT USE THESE IN ANY NEW CODE                              *
      *----------------------------------------------------------------*
      * 01  WS-BROKEN-YEAR-YY     PIC 9(2).   <-- THE PROBLEM        *
      * -- when year=2000, this field becomes 00                      *
      * -- CALC-INTEREST-YR subtracted years as 2-digit integers      *
      * -- result: (00 - 99) = -99 years of interest                 *
      * -- loan duration became NEGATIVE                              *
      * -- this is not a edge case. this is midnight jan 1.           *
      *----------------------------------------------------------------*

       PROCEDURE DIVISION.

       0000-MAIN.
           PERFORM 1000-INITIALIZE
           PERFORM 2000-PROCESS-RECORDS
               UNTIL WS-END-OF-FILE = 'Y'
           PERFORM 9000-TERMINATE
           STOP RUN.

       1000-INITIALIZE.
           OPEN INPUT  TRANS-FILE
           OPEN OUTPUT REPORT-FILE
           MOVE FUNCTION CURRENT-DATE(1:4) TO WS-CURR-YEAR
           MOVE FUNCTION CURRENT-DATE(5:2) TO WS-CURR-MONTH
           MOVE FUNCTION CURRENT-DATE(7:2) TO WS-CURR-DAY
           PERFORM 1100-READ-TRANS.

       1100-READ-TRANS.
           READ TRANS-FILE
               AT END MOVE 'Y' TO WS-END-OF-FILE.

       2000-PROCESS-RECORDS.
           ADD 1 TO WS-RECORD-COUNT
           PERFORM 2100-VALIDATE-DATE
           IF WS-DATE-VALID = 'Y'
               PERFORM 2200-CALC-INTEREST-YR
               PERFORM 2300-CHECK-MATURITY
           ELSE
               ADD 1 TO WS-ERROR-COUNT
               PERFORM 8000-WRITE-ERROR
           END-IF
           PERFORM 1100-READ-TRANS.

       2100-VALIDATE-DATE.
           MOVE 'Y' TO WS-DATE-VALID
           IF TR-YEAR < 1900 OR TR-YEAR > 2099
               MOVE 'N' TO WS-DATE-VALID
           END-IF
           IF TR-MONTH < 1 OR TR-MONTH > 12
               MOVE 'N' TO WS-DATE-VALID
           END-IF
           IF TR-DAY < 1 OR TR-DAY > 31
               MOVE 'N' TO WS-DATE-VALID
           END-IF.

       2200-CALC-INTEREST-YR.
      *----------------------------------------------------------------*
      * PATCHED VERSION -- 4-digit year subtraction                   *
      * Original (BROKEN):                                            *
      *   SUBTRACT WS-BROKEN-YEAR-YY FROM TR-YEAR-YY                 *
      *   GIVING WS-DAYS-REMAINING                                    *
      *   (result was negative for year 2000)                         *
      *----------------------------------------------------------------*
           SUBTRACT WS-CURR-YEAR FROM TR-MAT-YEAR
               GIVING WS-DAYS-REMAINING
           MULTIPLY WS-DAYS-REMAINING BY WS-DAYS-IN-YEAR
               GIVING WS-DAYS-REMAINING
           IF WS-DAYS-REMAINING <= ZEROS
               MOVE ZEROS TO WS-INTEREST-AMT
           ELSE
               MOVE TR-AMOUNT TO WS-INTEREST-AMT
               MULTIPLY WS-INTEREST-RATE BY WS-DAYS-REMAINING
                   GIVING WS-INTEREST-AMT ROUNDED
           END-IF
           ADD 1 TO WS-PATCHED-COUNT.

       2300-CHECK-MATURITY.
           MOVE TR-MAT-YEAR  TO WS-COMP-YEAR
           MOVE TR-MAT-MONTH TO WS-COMP-MONTH
           MOVE TR-MAT-DAY   TO WS-COMP-DAY
           IF WS-COMP-YEAR < WS-CURR-YEAR
               PERFORM 2310-WRITE-MATURED
           ELSE IF WS-COMP-YEAR = WS-CURR-YEAR
               IF WS-COMP-MONTH < WS-CURR-MONTH
                   PERFORM 2310-WRITE-MATURED
               ELSE IF WS-COMP-MONTH = WS-CURR-MONTH
                   IF WS-COMP-DAY <= WS-CURR-DAY
                       PERFORM 2310-WRITE-MATURED
                   END-IF
               END-IF
           END-IF.

       2310-WRITE-MATURED.
           MOVE TR-ACCOUNT-ID TO REPORT-RECORD(1:12)
           MOVE ' MATURED ' TO REPORT-RECORD(13:9)
           WRITE REPORT-RECORD.

       8000-WRITE-ERROR.
           MOVE TR-ACCOUNT-ID TO REPORT-RECORD(1:12)
           MOVE ' DATE-ERROR ' TO REPORT-RECORD(13:12)
           WRITE REPORT-RECORD.

       9000-TERMINATE.
           CLOSE TRANS-FILE
           CLOSE REPORT-FILE.
