/*
 * epoch_calc.h
 * Meridian Remediation Team -- 1999-06-22
 *
 * Utility macros and inline functions for safe epoch/date arithmetic.
 * Include this instead of calling stdlib date functions directly.
 *
 * Rule: if you are using time_t, mktime(), or localtime() anywhere
 * in production code, include this header and use these wrappers.
 * The stdlib functions are not wrong -- but they are easy to misuse.
 * This header makes the right thing the easy thing.
 */

#ifndef MERIDIAN_EPOCH_CALC_H
#define MERIDIAN_EPOCH_CALC_H

#include <time.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* Constants                                                           */
/* ------------------------------------------------------------------ */

/* Seconds in a standard (non-leap) year */
#define SECS_PER_YEAR       31536000L

/* Seconds in a leap year */
#define SECS_PER_LEAP_YEAR  31622400L

/* Seconds in a day */
#define SECS_PER_DAY        86400L

/* Seconds in an hour */
#define SECS_PER_HOUR       3600L

/*
 * Unix epoch base year.
 * time_t = 0 corresponds to 1970-01-01 00:00:00 UTC.
 * This is not going to change. Do not hardcode anything else.
 */
#define UNIX_EPOCH_YEAR     1970

/*
 * tm_year offset.
 * struct tm.tm_year is years since 1900, not actual year.
 * ALWAYS add this when converting tm_year to a display year.
 * ALWAYS subtract this when setting tm_year from a display year.
 *
 * In year 2000: tm_year = 100. Add TM_YEAR_BASE -> 2000. Correct.
 * In year 2000: tm_year printed as "%02d" -> "100". Three digits. Broken.
 */
#define TM_YEAR_BASE        1900

/* ------------------------------------------------------------------ */
/* Macros                                                              */
/* ------------------------------------------------------------------ */

/* Get 4-digit year from struct tm. Use this. Always. */
#define TM_FULL_YEAR(tm_ptr)    ((tm_ptr)->tm_year + TM_YEAR_BASE)

/* Check if a 4-digit year is a leap year */
#define IS_LEAP_YEAR(y) \
    (((y) % 400 == 0) ? 1 : \
     ((y) % 100 == 0) ? 0 : \
     ((y) % 4   == 0) ? 1 : 0)

/* Days in February for a given year */
#define FEB_DAYS(y)     (IS_LEAP_YEAR(y) ? 29 : 28)

/* ------------------------------------------------------------------ */
/* Inline functions                                                    */
/* ------------------------------------------------------------------ */

/*
 * meridian_localtime_safe()
 *
 * Wrapper for localtime(). Fills a struct tm and verifies that
 * tm_year was correctly updated after rollover.
 *
 * Returns pointer to static struct tm, same as localtime().
 * Check return value -- NULL means time() or localtime() failed.
 */
static inline struct tm *meridian_localtime_safe(time_t *t) {
    struct tm *result;
    time_t now;

    if (t == NULL) {
        now = time(NULL);
        t = &now;
    }

    result = localtime(t);
    if (result == NULL) return NULL;

    /*
     * Sanity check: after year 2000 rollover, tm_year should be >= 100.
     * If it's < 0 or > 200, something is very wrong with the system clock.
     */
    if (result->tm_year < 0 || result->tm_year > 200) {
        return NULL;  /* caller should log this and halt */
    }

    return result;
}

/*
 * meridian_mktime_safe()
 *
 * Wrapper for mktime(). Takes a 4-digit year and sets tm_year correctly.
 * Use this when constructing a struct tm from year/month/day values.
 *
 * full_year: 4-digit year (e.g., 2000, not 100)
 * month:     1-12
 * day:       1-31
 */
static inline time_t meridian_mktime_safe(int full_year, int month, int day,
                                           int hour, int min, int sec) {
    struct tm t;
    memset(&t, 0, sizeof(t));

    t.tm_year  = full_year - TM_YEAR_BASE;  /* years since 1900 */
    t.tm_mon   = month - 1;                 /* 0-indexed */
    t.tm_mday  = day;
    t.tm_hour  = hour;
    t.tm_min   = min;
    t.tm_sec   = sec;
    t.tm_isdst = -1;

    return mktime(&t);
}

/*
 * meridian_days_since_epoch()
 *
 * Returns the number of whole days elapsed since the Unix epoch
 * (1970-01-01) for the given time_t value.
 *
 * Useful for date arithmetic that doesn't need sub-day precision.
 */
static inline long meridian_days_since_epoch(time_t t) {
    return (long)(t / SECS_PER_DAY);
}

/*
 * meridian_format_year()
 *
 * Writes a 4-digit year string into buf.
 * buf must be at least 5 bytes.
 * Returns buf for convenience.
 *
 * Use this instead of sprintf(buf, "%02d", tm->tm_year).
 * That pattern is the root cause of most of the damage we are fixing.
 */
static inline char *meridian_format_year(struct tm *t, char *buf) {
    int full_year = TM_FULL_YEAR(t);
    buf[0] = '0' + (full_year / 1000) % 10;
    buf[1] = '0' + (full_year / 100)  % 10;
    buf[2] = '0' + (full_year / 10)   % 10;
    buf[3] = '0' + (full_year)        % 10;
    buf[4] = '\0';
    return buf;
}

#endif /* MERIDIAN_EPOCH_CALC_H */
