# 2.1.1 - Sep 14, 2021

* FIX: Call correct clean up method when legacy jobs are finished

# 2.1.0 - Sep 10, 2021

* PERF: Don't pass step data in success callback to every batch

NOTE: This changes the structure of arguments passed to Batch callbacks, though we
also handle the old way of doing it (v2.0.2 and before) so it shouldn't affect
any in-progress batches you may have running.

# 2.0.2 - Sep 24, 2020

* PERF: Delete keys based on known values, instead of a glob
* PERF: Don't bother enqueing a `:complete` callback if no `on_failure` is specified

# 2.0.1 - Jun 1, 2020

* CHORE: Bump development dependency versions
* CHORE: Add .ruby-version file for easier development

# 2.0.0 - Feb 5, 2020

* BREAKING: Treat each parallel block as a distinct step

# 1.1.0 - Feb 5, 2020

* FEAT: use Sidekiq's wrapped option for improved logging

# 1.0.1 - May 7, 2019

* FIX: don't look up previous results in Redis if the key is nil

# 1.0.0 - Nov 5, 2018

Initial release.
