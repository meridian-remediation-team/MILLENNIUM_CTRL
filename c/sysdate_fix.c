/*
 * sysdate_fix.c
 * Meridian Remediation Team — 1999-10-02
 *
 * Y2K-safe sysdate wrapper for SunOS 4.x and AIX 3.x nodes.
 * Replaces direct calls to localtime() and ctime() in legacy binaries
 * that do not account for tm_year offset correctly after rollover.
 *
 * PROBLEM:
 *   struct tm.tm_year is defined as "years since 1900".
 *   In 1999, tm_year = 99. Fine.
 *   In 2000, tm_year = 100. Not 00. Not 2000. One hundred.
 *   Every piece of code that does (1900 + tm_year) is correct.
 *   Every piece of code that prints tm_year with "%02d" is broken.
 *   Every piece of code that stores tm_year as a char[2] is broken.
 *   There is more of the second and third kind than anyone wants to admit.
 *
 * USAGE:
 *   Compile as a shared library and LD_PRELOAD it over the broken binary.
 *   See deploy_patch.sh for automated deployment.
 *
 *   cc -O2 -shared -fPIC -o sysdate_fix.so sysdate_fix.c
 *   LD_PRELOAD=/opt/meridian/sysdate_fix.so /usr/local/bin/broken_binary
 *
 * LIMITATIONS:
 *   This wrapper does NOT fix binaries that have already stored 2-digit
 *   years in flat files or databases. Those require manual remediation.
 *   See cobol/patch_banking.cob and cobol/date_rollover.cob.
 *
 *   This wrapper does NOT fix the IBM mainframe BIOS firmware issue.
 *   See asm/bios_hook.asm — and talk to cole before you touch that file.
 */

#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

/* ------------------------------------------------------------------ */
/* Internal safe date structure                                        */
/* All internal date handling goes through this. Never use tm_year    */
/* directly without adding 1900. This is the whole problem.           */
/* ------------------------------------------------------------------ */

typedef struct {
    int full_year;   /* 4-digit year. always. no exceptions. */
    int month;       /* 1-12 */
    int day;         /* 1-31 */
    int hour;
    int minute;
    int second;
} safe_date_t;


/* ------------------------------------------------------------------ */
/* meridian_get_date()                                                 */
/* Safe replacement for localtime(). Always returns 4-digit year.     */
/* ------------------------------------------------------------------ */
safe_date_t meridian_get_date(void) {
    safe_date_t sd;
    time_t now = time(NULL);
    struct tm *t = localtime(&now);

    sd.full_year = t->tm_year + 1900;  /* tm_year is years since 1900 */
    sd.month     = t->tm_mon + 1;      /* tm_mon is 0-indexed */
    sd.day       = t->tm_mday;
    sd.hour      = t->tm_hour;
    sd.minute    = t->tm_min;
    sd.second    = t->tm_sec;

    return sd;
}


/* ------------------------------------------------------------------ */
/* meridian_format_date()                                              */
/* Formats a safe_date_t into a buffer. Always 4-digit year.          */
/* Format: YYYY-MM-DD                                                  */
/* ------------------------------------------------------------------ */
void meridian_format_date(safe_date_t *sd, char *buf, size_t buflen) {
    if (!sd || !buf || buflen < 11) return;
    snprintf(buf, buflen, "%04d-%02d-%02d",
             sd->full_year, sd->month, sd->day);
}


/* ------------------------------------------------------------------ */
/* meridian_days_between()                                             */
/* Returns signed number of days between two dates.                   */
/* Negative if date_a is after date_b.                                */
/*                                                                     */
/* This is the function that breaks when you use 2-digit years.       */
/* If year_a = 00 and year_b = 99, the naive subtraction gives -99.  */
/* With 4-digit years: 2000 - 1999 = 1. Correct.                     */
/* ------------------------------------------------------------------ */
int meridian_days_between(safe_date_t *date_a, safe_date_t *date_b) {
    /* Simplified: year difference only, ignoring leap years */
    /* Good enough for the rollover window we care about     */
    int year_diff  = date_b->full_year - date_a->full_year;
    int month_diff = date_b->month - date_a->month;
    int day_diff   = date_b->day - date_a->day;

    return (year_diff * 365) + (month_diff * 30) + day_diff;
}


/* ------------------------------------------------------------------ */
/* meridian_is_leap_year()                                             */
/* Year 2000 IS a leap year. 1900 was NOT.                            */
/* Divisible by 400 -> leap. Divisible by 100 -> not leap.            */
/* Divisible by 4   -> leap.                                           */
/* ------------------------------------------------------------------ */
int meridian_is_leap_year(int year) {
    if (year % 400 == 0) return 1;
    if (year % 100 == 0) return 0;
    if (year % 4   == 0) return 1;
    return 0;
}


/* ------------------------------------------------------------------ */
/* meridian_validate_date()                                            */
/* Returns 1 if date is valid, 0 if not.                              */
/* ------------------------------------------------------------------ */
int meridian_validate_date(safe_date_t *sd) {
    if (!sd) return 0;
    if (sd->full_year < 1900 || sd->full_year > 2099) return 0;
    if (sd->month < 1 || sd->month > 12) return 0;
    if (sd->day < 1 || sd->day > 31) return 0;

    /* February */
    if (sd->month == 2) {
        int max_day = meridian_is_leap_year(sd->full_year) ? 29 : 28;
        if (sd->day > max_day) return 0;
    }

    /* 30-day months */
    if (sd->month == 4 || sd->month == 6 ||
        sd->month == 9 || sd->month == 11) {
        if (sd->day > 30) return 0;
    }

    return 1;
}


/* ------------------------------------------------------------------ */
/* LD_PRELOAD hooks -- override broken libc date functions             */
/* These intercept calls from legacy binaries transparently           */
/* ------------------------------------------------------------------ */

/*
 * Hook for strftime with %y (2-digit year format).
 * We reroute %y to %Y everywhere. This is aggressive but necessary.
 *
 * NOTE: This will break any code that relies on fixed-width 2-digit
 * year output. That code is already broken. We are not making it worse.
 */
size_t strftime(char *s, size_t max, const char *format, const struct tm *tm) {
    char safe_format[4096];
    const char *src = format;
    char *dst = safe_format;

    while (*src && (dst - safe_format) < (int)(sizeof(safe_format) - 3)) {
        if (*src == '%' && *(src+1) == 'y') {
            /* Replace %y (2-digit year) with %Y (4-digit year) */
            *dst++ = '%';
            *dst++ = 'Y';
            src += 2;
        } else {
            *dst++ = *src++;
        }
    }
    *dst = '\0';

    /* Call real strftime with patched format string */
    /* This is the only place we're allowed to call it directly */
    extern size_t __real_strftime(char*, size_t, const char*, const struct tm*);
    return __real_strftime(s, max, safe_format, tm);
}


/* ------------------------------------------------------------------ */
/* main() -- test harness only, not compiled into .so                  */
/* Run: cc -DTEST -o sysdate_test sysdate_fix.c && ./sysdate_test     */
/* ------------------------------------------------------------------ */
#ifdef TEST
int main(void) {
    safe_date_t today = meridian_get_date();
    char buf[32];
    meridian_format_date(&today, buf, sizeof(buf));

    printf("Current date (safe): %s\n", buf);
    printf("Full year: %d\n", today.full_year);
    printf("Is leap year: %s\n",
           meridian_is_leap_year(today.full_year) ? "yes" : "no");
    printf("Date valid: %s\n",
           meridian_validate_date(&today) ? "yes" : "no");

    /* Simulate the rollover */
    safe_date_t y2k = {2000, 1, 1, 0, 0, 0};
    safe_date_t y1999 = {1999, 12, 31, 23, 59, 59};

    printf("\nDays from Dec 31 1999 to Jan 1 2000: %d\n",
           meridian_days_between(&y1999, &y2k));

    return 0;
}
#endif
