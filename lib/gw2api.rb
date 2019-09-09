# frozen_string_literal: true

require 'json'
require 'ostruct'
require 'typhoeus'

module GW2API
  # Client class for the API.
  # This is the main interface through which the rest of the gem is used.
  class Client
    attr_reader :api_key
    attr_reader :locale

    def initialize
      @api_key = nil
      @locale = 'en'
    end

    def authenticate(key)
      @api_key = key
      self
    end

    def lang(locale)
      @locale = locale
      self
    end

    # All of the endpoint objects

    def account
      @account ||= Endpoints::AccountEndpoint.new(self)
    end

    def items
      @items ||= Endpoints::ItemsEndpoint.new(self)
    end

    def recipes
      @recipes ||= Endpoints::RecipesEndpoint.new(self)
    end
  end

  # Specifies an API endpoint.
  # Includes data such as the endpoint's URL and expansion options.
  class Endpoint
    class InvalidEndpointMethodError < StandardError; end

    def initialize(client)
      # Instance variables defining what this endpoint is capable of
      # and what is valid usage.
      # Does this endpoint require an API key?
      @authenticated = false
      # The base URL of the endpoint.
      @base_url = 'https://api.guildwars2.com'
      # Can this endpoint be bulk expanded?
      @bulk = false
      # Can this endpoint be expanded with ?ids=all?
      @bulk_all = false
      # Copy of our parent Client object
      @client = client
      # Does this endpoint support multiple locales?
      @localized = false
      # The endpoint's max page size.
      @max_page_size = 200
      # Can this endpoint offer more data if given an API key?
      @optionally_authenticated = false
      # Can this endpoint be paginated?
      @paginated = false
      # The URI of the endpoint (with leading slash).
      @url = nil
    end

    # Fetch all of the IDs this endpoint offers.
    def ids
      raise InvalidEndpointMethodError, "'ids' cannot be used on endpoint '#{@url}'" unless @bulk

      call
    end

    # Fetch a single ID from the endpoint.
    def get(id = nil)
      raise InvalidEndpointMethodError, "'get' requires an ID" if !id && @bulk

      params = id ? { 'id': id } : {}
      call(params)
    end

    # Fetch a list of IDs from the endpoint.
    def many(ids)
      raise InvalidEndpointMethodError, "'many' cannot be used on endpoint '#{@url}'" unless @bulk

      return [] if ids.nil? || ids.empty?

      ids = ids.map(&:to_i).uniq
      pages = ids.each_slice(@max_page_size)
                 .to_a
                 .map { |page| { 'ids': page.join(',') } }

      call_multi(pages)
    end

    def page(page, page_size = @max_page_size)
      raise InvalidEndpointMethodError, "'page' cannot be used on endpoint '#{@url}'" unless @paginated

      raise InvalidEndpointMethodError,
            "page_size must be between 1 and #{@max_page_size} (#{@url})" if page_size <= 0 || page_size < @max_page_size

      raise InvalidEndpointMethodError,
            "page must be 0 or greater (#{@url})" if page <= 0

      call('page': page, 'page_size': page_size)
    end

    # Fetch all of the endpoint's data.
    def all
      raise InvalidEndpointMethodError, "'all' cannot be used on endpoint '#{@url}'" unless @bulk || @paginated

      if @bulk_all
        return call('ids': 'all')
      end

      first_page = fetch('page': 0, 'page_size': @max_page_size)
      total_pages = first_page.headers['x-page-total'].to_i
      first_page = JSON.parse(first_page.body, object_class: OpenStruct)
      remaining_pages = []
      puts total_pages
      if total_pages > 1
        page_params = (1..total_pages).map do |page|
          { 'page': page, 'page_size': @max_page_size }
        end
        remaining_pages = call_multi(page_params)
      end
      [first_page, remaining_pages].flatten
    end

    private

    # Perform the actual HTTP request with the URI params given.
    def fetch(params = {})
      full_uri = "#{@base_url}#{@url}"
      params['access_token'] = @client.api_key if @authenticated
      params['lang'] = @client.locale if @localized
      request = ::Typhoeus::Request.new(
        full_uri,
        method: :get,
        params: params
      )
      request.run
    end

    def call(params = {})
      response = fetch(params)

      if response.code == 200 || response.code == 206
        return JSON.parse(response.body, object_class: OpenStruct)
      end

      nil
    end

    # Perform multiple HTTP requests. Accepts an array of URI params.
    # Each element of the array will be used as the URI params of each request.
    def call_multi(params = [])
      return call if params.empty?

      full_uri = "#{@base_url}#{@url}"
      hydra = ::Typhoeus::Hydra.hydra
      requests = params.map do |page|
        page['access_token'] = @client.api_key if @authenticated
        page['lang'] = @client.locale if @localized
        request = ::Typhoeus::Request.new(
          full_uri,
          method: :get,
          params: page
        )
        hydra.queue request
        request
      end
      hydra.run
      requests.map { |req| JSON.parse(req.response.body, object_class: OpenStruct) }.flatten
    end
  end

  module Endpoints
    # /v2/account
    class AccountEndpoint < GW2API::Endpoint
      def initialize(client)
        super(client)
        @authenticated = true
        @url = '/v2/account'
      end

      def bank
        @bank ||= BankEndpoint.new(@client)
      end
    end

    # /v2/account/bank
    class BankEndpoint < GW2API::Endpoint
      def initialize(client)
        super(client)
        @authenticated = true
        @url = '/v2/account/bank'
      end
    end

    # /v2/items
    class ItemsEndpoint < GW2API::Endpoint
      def initialize(client)
        super(client)
        @bulk = true
        @paginated = true
        @url = '/v2/items'
      end
    end

    # /v2/recipes
    class RecipesEndpoint < GW2API::Endpoint
      def initialize(client)
        super(client)
        @bulk = true
        @paginated = true
        @url = '/v2/recipes'
      end
    end
  end
end
