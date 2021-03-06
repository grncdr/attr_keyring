# frozen_string_literal: true

module Keyring
  require "openssl"
  require "base64"
  require "digest/sha1"

  require "keyring/key"
  require "keyring/encryptor/aes"

  UnknownKey = Class.new(StandardError)
  InvalidSecret = Class.new(StandardError)
  EmptyKeyring = Class.new(StandardError)
  InvalidAuthentication = Class.new(StandardError)
  MissingDigestSalt = Class.new(StandardError) do
    def message
      %w[
        Please provide :digest_salt;
        you can disable this error by explicitly passing an empty string.
      ].join(" ")
    end
  end

  class Base
    def initialize(keyring, options)
      @encryptor = options[:encryptor]
      @digest_salt = options[:digest_salt]
      @keyring = keyring.map do |id, value|
        Key.new(id, value, @encryptor.key_size)
      end
    end

    def current_key
      @keyring.max_by(&:id)
    end

    def [](id)
      raise EmptyKeyring, "keyring doesn't have any keys" if @keyring.empty?

      key = @keyring.find {|k| k.id == id.to_i }
      return key if key

      raise UnknownKey, "key=#{id} is not available on keyring"
    end

    def []=(id, key)
      @keyring << Key.new(id, key, @encryptor.key_size)
    end

    def clear
      @keyring.clear
    end

    def encrypt(message, keyring_id = nil)
      keyring_id ||= current_key&.id
      key = self[keyring_id]

      [
        @encryptor.encrypt(key, message),
        keyring_id,
        digest(message)
      ]
    end

    def decrypt(message, keyring_id)
      key = self[keyring_id]
      @encryptor.decrypt(key, message)
    end

    def digest(message)
      Digest::SHA1.hexdigest("#{message}#{@digest_salt}")
    end
  end

  def self.new(keyring, options = {})
    options = {
      encryptor: Encryptor::AES::AES128CBC
    }.merge(options)

    raise MissingDigestSalt if options[:digest_salt].nil?

    Base.new(keyring, options)
  end
end
