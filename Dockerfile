FROM ruby:2.3.5-slim
MAINTAINER zan@whiteants.net

#Image for Redmine v 3.4.4, from ruby 2.3.5, Rails 4.2, Passenger 5.1.12
# ruby use v2.3.5 for build native_binary_support of Passenger, but Passenger supplu max ruby v2.4.2, and next down version 2.3.5
# ruby v2.4.2. don't support Redmine v 3.4.4,  Redmine support ruby v2.3.5, 2.3.6 or 2.4.3

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added

ENV PASSENGER_VERSION=5.1.12
# this oli list plugins for build inside container
ENV PLUGINS="sidebar_hide fixed_header drawio vote_on_issues wiki_lists plugin_views_revisions redmineup_tags \
 										  zenedit theme_changer a_common_libs unread_issues issue_tabs usability user_specific_theme view_customize \
											wiki_extensions easy_mindmup easy_wbs redhopper issue_id issue_todo_lists category_tree"

RUN groupadd -r redmine && useradd -r -g redmine -m -d /home/redmine redmine

RUN apt-get update && apt-get install -y --no-install-recommends \
		ca-certificates \
		wget \
	&& rm -rf /var/lib/apt/lists/*

# grab gosu for easy step-down from root
ENV GOSU_VERSION 1.10
RUN set -x \
	&& wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
	&& wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
	&& gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
	&& rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc \
	&& chmod +x /usr/local/bin/gosu \
	&& gosu nobody true

# grab tini for signal processing and zombie killing
ENV TINI_VERSION v0.16.1
RUN set -x \
	&& wget -O /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-$(dpkg --print-architecture)" \
	&& wget -O /usr/local/bin/tini.asc "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini-$(dpkg --print-architecture).asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 6380DC428747F6C393FEACA59A84159D7001A4E5 \
	&& gpg --batch --verify /usr/local/bin/tini.asc /usr/local/bin/tini \
	&& rm -r "$GNUPGHOME" /usr/local/bin/tini.asc \
	&& chmod +x /usr/local/bin/tini \
	&& tini -h

RUN apt-get update && apt-get install -y --no-install-recommends \
		imagemagick \
		libmysqlclient18 \
		libpq5 \
		\
		bzr \
		git \
		mercurial \
		openssh-client \
		subversion \
	&& rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV production
WORKDIR /usr/src/redmine

ENV REDMINE_VERSION 3.4.4
ENV REDMINE_DOWNLOAD_MD5 8152aa9fd2d5d01cf50ad898090b1d78

RUN wget -O redmine.tar.gz "https://www.redmine.org/releases/redmine-${REDMINE_VERSION}.tar.gz" \
	&& echo "$REDMINE_DOWNLOAD_MD5 redmine.tar.gz" | md5sum -c - \
	&& tar -xvf redmine.tar.gz --strip-components=1 \
	&& rm redmine.tar.gz files/delete.me log/delete.me \
	&& mkdir -p tmp/pdf public/plugin_assets \
	&& chown -R redmine:redmine ./

#install gems for redmine, install passenger and gems for plugins
RUN buildDeps=' \
		gcc \
		libmagickcore-dev \
		libmagickwand-dev \
		libmysqlclient-dev \
		libpq-dev \
		libsqlite3-dev \
		make \
		patch \
	' \
	&& set -ex \
	&& apt-get update && apt-get install -y $buildDeps --no-install-recommends \
	&& rm -rf /var/lib/apt/lists/* \
  # add bundle setting and updates for install plugins
  && bundle install --without development test \
  && for adapter in postgresql; do \
		echo "$RAILS_ENV:" > ./config/database.yml; \
		echo "  adapter: $adapter" >> ./config/database.yml; \
		bundle install --without development test; \
    rake generate_secret_token; \
    cp Gemfile.lock "Gemfile.lock.${adapter}"; \
	done \
  # install passenger
  && gem install passenger --version "$PASSENGER_VERSION" \
  # install gems reguired for plugins
  && gem install acts_as_list \
  && gem install redmine_crm \
  && gem install haml --version 4.0.7 \
  && gem install multi_json --version 1.13.1\
  && gem install activerecord-session_store --version 1.1.0 \
  && gem install awesome_nested_set --version 3.1.4 \
  && gem install sexp_processor --version 4.10.0 \
  && gem install ruby_parser --version 3.10.1 \
  && gem install html2haml --version 2.2.0 \
  && gem install haml-rails --version 1.0.0 \
  && gem install redmine_extensions --version 0.2.7 \
  && gem install require_patch --version 0.3.3 \
  && gem install rubyzip --version 1.2.1 \
  && rm ./config/database.yml \
	&& apt-get purge -y --auto-remove $buildDeps

  RUN set -x \
    && mkdir hide-plugins \
    && cd hide-plugins \
  #	sidebar_hide) \
    && git clone https://github.com/bdemirkir/sidebar_hide.git \
  #	fixed_header) \
    && git clone https://github.com/YujiSoftware/redmine-fixed-header.git redmine_fixed_header \
  #	drawio) \
    && git clone https://github.com/mikitex70/redmine_drawio.git \
  #	vote_on_issues) \
    && git clone https://github.com/ojde/redmine-vote_on_issues-plugin.git vote_on_issues \
  #	wiki_lists) \
    && git clone https://github.com/tkusukawa/redmine_wiki_lists.git \
  #	plugin_views_revisions) \
    && git clone https://github.com/mochan-tk/redmine_plugin_views_revisions.git \
  #	tags) \
  #	git clone https://github.com/ixti/redmine_tags.git  ;; \
  #	zenedit) \
    && git clone https://github.com/RCRM/redmine_zenedit.git \
  # redmineup_tags  - plugin from REDMINEUP.COM
    && git clone  https://github.com/abhinand-tw/redmineup_tags.git \
  #	theme_changer) \
    && git clone https://github.com/haru/redmine_theme_changer.git \
  #	a_common_libs) \
    && git clone https://github.com/abhinand-tw/a_common_libs.git \
  #	unread_issues) \
    && git clone https://github.com/abhinand-tw/unread_issues.git \
  #	issue_tabs) \
    && git clone https://github.com/abhinand-tw/redmine_issue_tabs.git \
  #	usability) \
    && git clone https://github.com/abhinand-tw/usability.git \
  #	user_specific_theme) \
    && git clone https://github.com/Restream/redmine_user_specific_theme.git \
  #	view_customize) \
    && git clone https://github.com/onozaty/redmine-view-customize.git view_customize \
  #	wiki_extensions) \
    && git clone https://github.com/haru/redmine_wiki_extensions.git \
  #	issue_id) \
    && git clone https://github.com/s-andy/issue_id.git \
  #	issue_todo_lists) \
    && git clone https://github.com/canidas/redmine_issue_todo_lists.git \
  #	category_tree) \
  # git clone https://github.com/bap14/redmine_category_tree.git  # original repo;
  #repo abhinand-tw patched version from issue_id
    && git clone  https://github.com/abhinand-tw/redmine_category_tree.git \
  #	easy_mindmup) \
    && git clone https://github.com/abhinand-tw/easy_mindmup.git \
  #	easy_wbs) \
    && git clone https://github.com/abhinand-tw/easy_wbs.git \
  #	redhopper) \
    && git clone https://framagit.org/infopiiaf/redhopper.git \
    && cd .. \
    && chown -R redmine:redmine hide-plugins \
    && chown redmine:redmine hide-plugins \
    && chown -R redmine:redmine plugins \
    && chown redmine:redmine plugins \
    # https://www.redmine.org/projects/redmine/wiki/RedmineInstall#Step-8-File-system-permissions
    && chown -R redmine:redmine files log public/plugin_assets \
    # directories 755, files 644:
    && chmod -R ugo-x,u+rwX,go+rX,go-w files log tmp public/plugin_assets \
    # init passenger and install nginx engine for www
    && passenger-config install-agent \
  	&& passenger-config download-nginx-engine

VOLUME /usr/src/redmine/files

COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 3000
CMD ["passenger", "start"]
