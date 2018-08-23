class CalendarWorker
    include Worker

    ORIGIN_KEY = "calendars:announce-origin"
    ANNOUNCE_KEY = "calendars:announce"

    # Pull events from google calendar and cache them in redis.
    # Slow it down in non-production environments, because API requests are limited.

    def self.polling_interval
        if Rails.env.production?
            1.minute
        else
            5.minutes
        end
    end

    poll delay: polling_interval do
        to_announce = []

        # Ensure token never expires
        GOOGLE::CALENDAR.authorization.fetch_access_token!

        Calendar.all.each do |cal|
          logger.info "Getting events for " + cal.id

          # Save ALL upcoming events
          items = GOOGLE::CALENDAR.list_events(cal.source, time_min: (Time.now).to_datetime.rfc3339).items
          next if items.empty? # Calendar is empty

          full = {}
          items.each do |event|
            full[event.id.to_sym] = hashify(cal.id, event)
          end

          REDIS.set("calendars:#{cal.id}:upcoming", full.to_json)
          REDIS.expire("calendars:#{cal.id}:upcoming", 15.minutes)

          # Save closest event
          event = items.first
          REDIS.set("calendars:#{cal.id}:next", hashify(cal.id, event).to_json)
          REDIS.expire("calendars:#{cal.id}:next", 15.minutes)

          # Announce events that are less than a week away
          if cal.announce &&
              (event.start.date != nil && Date.parse(event.start.date).mjd - Date.today.mjd <= cal.announce_range) ||
              (event.start.date_time != nil && Date.parse(event.start.date_time.to_date).mjd - Date.today.mjd <= cal.announce_range)

            to_announce << [cal.id, event]
          end
        end

        if to_announce.empty?
          logger.info "Nothing to announce! Clearing cache..."
          REDIS.del(ANNOUNCE_KEY)
          REDIS.del(ORIGIN_KEY)
          next # return
        end

        # Announce nearest event
        to_announce.sort_by!{|e| e[1].start.date_time}

        event = to_announce.first
        REDIS.set(ANNOUNCE_KEY, hashify(event[0], event[1]).to_json)
        REDIS.expire(ANNOUNCE_KEY, 10.minutes)
        REDIS.set(ORIGIN_KEY, event[0])
        REDIS.expire(ORIGIN_KEY, 10.minutes)
    end

    def hashify(cal, event)
      {
        calendar: cal,                      # id (defined by us) of containing calendar
        id: event.id.to_sym,                # Google event ID
        summary: event.summary,             # Title of the event
        description: event.description,     # Description of the event (HTML)
        # For all day events:
        start_date: event.start.date,       # Date the event starts for all day events
        end_date: event.end.date,           # Date the event events for all day events
        # All day events don't have these:
        start_time: event.start.date_time,  # Date and time the event starts for non all day events
        end_time: event.end.date_time       # Date and time the event starts for non all day events
      }
    end
end
