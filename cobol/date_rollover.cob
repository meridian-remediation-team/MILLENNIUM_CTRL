      *================================================================*
      * PROGRAM:    DATE-ROLLOVER                                      *
      * AUTHOR:     MERIDIAN REMEDIATION TEAM                         *
      * DATE:       1999-11-03                                         *
      * PURPOSE:    GENERIC Y2K DATE COMPARISON AND ROLLOVER PATCH    *
      *             FOR USE IN BILLING AND BATCH RUNNER MODULES        *
      *             TARGET: billrun, accrual_batch, stmt_gen           *
      *================================================================*
      *
      * This module provides Y2K-safe date comparison and arithmetic
      * as callable subroutines. Link against this instead of rolling
      * your own date logic. We've seen what happens when you roll
      * your own date logic.
      *
      * Entry points:
      *   COMPARE-DATES    -- compares two YYYYMMDD dates
      *   ADD-DAYS-TO-DATE -- adds N days to a YYYYMMDD date
      *   DAYS-BETWEEN     -- returns signed days between two dates
      *   FORMAT-DATE-SAFE -- formats date as printable string (YYYY-MM-DD)
      *
      *================================================================*

       IDENTIFICATION DIVISION.
       PROGRAM-ID. DATE-ROLLOVER.
       AUTHOR. MERIDIAN-OPS.
       DATE-WRITTEN. 1999-11-03.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-3090.
       OBJECT-COMPUTER. IBM-3090.

       DATA DIVISION.

       WORKING-STORAGE SECTION.

      *----------------------------------------------------------------*
      * Shared date work areas                                         *
      *----------------------------------------------------------------*
       01  WS-DATE-A.
           05  WS-DATE-A-YYYY    PIC 9(4).
           05  WS-DATE-A-MM      PIC 9(2).
           05  WS-DATE-A-DD      PIC 9(2).

       01  WS-DATE-B.
           05  WS-DATE-B-YYYY    PIC 9(4).
           05  WS-DATE-B-MM      PIC 9(2).
           05  WS-DATE-B-DD      PIC 9(2).

       01  WS-JULIAN-A           PIC 9(9)  VALUE ZEROS.
       01  WS-JULIAN-B           PIC 9(9)  VALUE ZEROS.
       01  WS-DIFF               PIC S9(9) VALUE ZEROS.
       01  WS-TEMP               PIC 9(9)  VALUE ZEROS.
       01  WS-LEAP-FLAG          PIC X(1)  VALUE 'N'.

       01  WS-MONTHS-DAYS.
           05  FILLER PIC 9(2) VALUE 31.   *> Jan
           05  FILLER PIC 9(2) VALUE 28.   *> Feb (non-leap)
           05  FILLER PIC 9(2) VALUE 31.   *> Mar
           05  FILLER PIC 9(2) VALUE 30.   *> Apr
           05  FILLER PIC 9(2) VALUE 31.   *> May
           05  FILLER PIC 9(2) VALUE 30.   *> Jun
           05  FILLER PIC 9(2) VALUE 31.   *> Jul
           05  FILLER PIC 9(2) VALUE 31.   *> Aug
           05  FILLER PIC 9(2) VALUE 30.   *> Sep
           05  FILLER PIC 9(2) VALUE 31.   *> Oct
           05  FILLER PIC 9(2) VALUE 30.   *> Nov
           05  FILLER PIC 9(2) VALUE 31.   *> Dec
       01  WS-MONTH-TABLE REDEFINES WS-MONTHS-DAYS
                              PIC 9(2) OCCURS 12 TIMES.

      *----------------------------------------------------------------*
      * Linkage section -- interface for callers                       *
      *----------------------------------------------------------------*
       LINKAGE SECTION.

       01  LS-DATE-IN-1          PIC 9(8).   *> YYYYMMDD
       01  LS-DATE-IN-2          PIC 9(8).   *> YYYYMMDD
       01  LS-DAYS-IN            PIC S9(9).
       01  LS-DATE-OUT           PIC 9(8).   *> YYYYMMDD result
       01  LS-RESULT             PIC S9(9).  *> signed result / comparison
       01  LS-STRING-OUT         PIC X(10).  *> "YYYY-MM-DD"
       01  LS-RETURN-CODE        PIC 9(2).   *>  0=OK 1=invalid date 2=overflow

       PROCEDURE DIVISION.

      *================================================================*
      * COMPARE-DATES                                                  *
      * IN:  LS-DATE-IN-1, LS-DATE-IN-2 (both YYYYMMDD)              *
      * OUT: LS-RESULT  < 0 if date1 < date2                         *
      *                = 0 if equal                                   *
      *                > 0 if date1 > date2                           *
      *      LS-RETURN-CODE  0=OK, 1=invalid input                    *
      *================================================================*
       COMPARE-DATES.
           PERFORM UNPACK-DATE-A USING LS-DATE-IN-1
           PERFORM UNPACK-DATE-B USING LS-DATE-IN-2
           PERFORM VALIDATE-DATE-A
           PERFORM VALIDATE-DATE-B
           PERFORM DATE-TO-JULIAN USING WS-DATE-A WS-JULIAN-A
           PERFORM DATE-TO-JULIAN USING WS-DATE-B WS-JULIAN-B
           SUBTRACT WS-JULIAN-B FROM WS-JULIAN-A GIVING LS-RESULT
           MOVE 0 TO LS-RETURN-CODE
           GOBACK.

      *================================================================*
      * DAYS-BETWEEN                                                   *
      * Same as COMPARE-DATES but semantics are date2 - date1         *
      *================================================================*
       DAYS-BETWEEN.
           PERFORM UNPACK-DATE-A USING LS-DATE-IN-1
           PERFORM UNPACK-DATE-B USING LS-DATE-IN-2
           PERFORM DATE-TO-JULIAN USING WS-DATE-A WS-JULIAN-A
           PERFORM DATE-TO-JULIAN USING WS-DATE-B WS-JULIAN-B
           SUBTRACT WS-JULIAN-A FROM WS-JULIAN-B GIVING LS-RESULT
           MOVE 0 TO LS-RETURN-CODE
           GOBACK.

      *================================================================*
      * FORMAT-DATE-SAFE                                               *
      * IN:  LS-DATE-IN-1 (YYYYMMDD)                                  *
      * OUT: LS-STRING-OUT "YYYY-MM-DD"                               *
      *================================================================*
       FORMAT-DATE-SAFE.
           PERFORM UNPACK-DATE-A USING LS-DATE-IN-1
           STRING WS-DATE-A-YYYY '-' WS-DATE-A-MM '-' WS-DATE-A-DD
               DELIMITED SIZE INTO LS-STRING-OUT
           MOVE 0 TO LS-RETURN-CODE
           GOBACK.

      *----------------------------------------------------------------*
      * Internal routines                                              *
      *----------------------------------------------------------------*

       UNPACK-DATE-A.
      *> Split YYYYMMDD integer into year/month/day fields
           DIVIDE LS-DATE-IN-1 BY 10000 GIVING WS-DATE-A-YYYY
               REMAINDER WS-TEMP
           DIVIDE WS-TEMP BY 100 GIVING WS-DATE-A-MM
               REMAINDER WS-DATE-A-DD.

       UNPACK-DATE-B.
           DIVIDE LS-DATE-IN-2 BY 10000 GIVING WS-DATE-B-YYYY
               REMAINDER WS-TEMP
           DIVIDE WS-TEMP BY 100 GIVING WS-DATE-B-MM
               REMAINDER WS-DATE-B-DD.

       VALIDATE-DATE-A.
           MOVE 0 TO LS-RETURN-CODE
           IF WS-DATE-A-YYYY < 1900 OR WS-DATE-A-YYYY > 2099
               MOVE 1 TO LS-RETURN-CODE
           END-IF
           IF WS-DATE-A-MM < 1 OR WS-DATE-A-MM > 12
               MOVE 1 TO LS-RETURN-CODE
           END-IF.

       VALIDATE-DATE-B.
           IF WS-DATE-B-YYYY < 1900 OR WS-DATE-B-YYYY > 2099
               MOVE 1 TO LS-RETURN-CODE
           END-IF
           IF WS-DATE-B-MM < 1 OR WS-DATE-B-MM > 12
               MOVE 1 TO LS-RETURN-CODE
           END-IF.

       IS-LEAP-YEAR.
      *> Year 2000 IS a leap year. 1900 was NOT.
           MOVE 'N' TO WS-LEAP-FLAG
           IF FUNCTION MOD(WS-DATE-A-YYYY, 400) = 0
               MOVE 'Y' TO WS-LEAP-FLAG
           ELSE
               IF FUNCTION MOD(WS-DATE-A-YYYY, 100) = 0
                   MOVE 'N' TO WS-LEAP-FLAG
               ELSE
                   IF FUNCTION MOD(WS-DATE-A-YYYY, 4) = 0
                       MOVE 'Y' TO WS-LEAP-FLAG
                   END-IF
               END-IF
           END-IF.

       DATE-TO-JULIAN.
      *> Simplified Julian Day Number calculation.
      *> Accurate enough for date arithmetic in the 1970-2099 window.
           COMPUTE WS-JULIAN-A =
               365 * WS-DATE-A-YYYY
               + FUNCTION INTEGER(WS-DATE-A-YYYY / 4)
               - FUNCTION INTEGER(WS-DATE-A-YYYY / 100)
               + FUNCTION INTEGER(WS-DATE-A-YYYY / 400)
               + WS-DATE-A-DD
               + FUNCTION INTEGER((153 * WS-DATE-A-MM + 2) / 5)
               - 32045.
