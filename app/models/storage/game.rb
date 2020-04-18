class Storage::Game < ApplicationRecord
  module GzipJSON
    extend self

    def load(data)
      if data && data.getbyte(0) == 31 && data.getbyte(1) == 139
        data = Zlib.gunzip(data)
      end
      JSON.load(data)
    end

    def dump(data)
      Zlib.gzip(JSON.dump(data))
    end
  end

  serialize :initial_state, JSON
  serialize :move_data, GzipJSON

  has_many :moves

  validates :initial_state, :external_id, :snake_version, presence: true

  def human_victory
    { true => "won", false => "lost" }[victory]
  end

  def human_result
    return if victory.nil?
    "#{human_victory} in #{moves.count} turns"
  end

  def external_url
    "https://play.battlesnake.com/g/#{external_id}/"
  end

  def gif_url
    "https://exporter.battlesnake.com/games/#{external_id}/gif"
  end

  def turn_image_url(turn)
    "https://exporter.battlesnake.com/games/#{external_id}/frames/#{turn}/gif"
  end

  def to_param
    external_id
  end
end
