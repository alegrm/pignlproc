/**
 * This scripts is used to identify the categories that have matching
 * dbpedia resource (with label, abstract...). We call such categories
 * "grounded topics".
 */

SET default_parallel 20

-- Register the project jar to use the custom loaders and UDFs
REGISTER target/pignlproc-0.1.0-SNAPSHOT.jar
DEFINE checkAbstract pignlproc.evaluation.CheckAbstract('30');

topic_counts = LOAD 'workspace/topics_counts.tsv'
  AS (topicUri: chararray, articleCount: long, narrowerTopicCount:long,
      broaderTopicCount);

topic_parents = LOAD 'workspace/skos_categories_en.nt.bz2'
  USING pignlproc.storage.UriUriNTriplesLoader(
    'http://www.w3.org/2004/02/skos/core#broader',
    'http://dbpedia.org/resource/',
    'http://dbpedia.org/resource/')
  AS (narrowerTopicUri: chararray, broaderTopicUri: chararray);

article_abstracts = LOAD 'workspace/long_abstracts_en.nt.bz2'
  USING pignlproc.storage.UriStringLiteralNTriplesLoader(
    'http://dbpedia.org/ontology/abstract',
    'http://dbpedia.org/resource/')
  AS (articleUri: chararray, articleAbstract: chararray);

redirects = LOAD 'workspace/redirects_en.nt.bz2'
  USING pignlproc.storage.UriUriNTriplesLoader(
    'http://dbpedia.org/ontology/wikiPageRedirects',
    'http://dbpedia.org/resource/',
    'http://dbpedia.org/resource/')
  AS (source: chararray, target: chararray);

-- Remove boring topics as early as possible: those topics do no bring
-- much classification information outside of Wikipedia.

topic_counts_filtered = FILTER topic_counts BY
  topicUri != 'Category:People'
  AND topicUri != 'Category:Living_people'
  AND topicUri != 'Category:Dead_people'
  AND topicUri != 'Category:Missing_people'
  AND topicUri != 'Category:Chronology'
  AND topicUri != 'Category:Events'
  AND topicUri != 'Category:Years'
  AND topicUri != 'Category:Decads'
  AND topicUri != 'Category:Days'
  AND topicUri != 'Category:Dates'
  AND topicUri != 'Category:Time'
  AND topicUri != 'Category:Calendars'
  AND topicUri != 'Category:Months'
  AND topicUri != 'Year_of_birth_missing_%28living_people%29'
  AND topicUri != 'Year_of_death_missing'
  AND topicUri != 'Place_of_birth_missing_%28living_people%29'
  AND topicUri != 'Category:Year_of_birth_unknown'
  AND topicUri != 'Category:Year_of_birth_missing_%28living_people%29'
  AND topicUri != 'Category:Articles_missing_birth_or_death_information'
  AND topicUri != 'Category:Place_of_birth_missing_%28living_people%29'
  AND topicUri != 'Category:Surnames'
  AND topicUri != 'Category:Wikipedia_1.0_assessments'
  AND topicUri != 'Category:Categories_by_language'
  AND topicUri != 'Category:People_by_period';

-- AGRM and filter those that have _by_ on the category
-- topic_counts_filtered2 = FILTER topic_counts_filtered BY not topicUri matches '.*_by_.*';

-- AGRM start: get the children of undesired topics to remove them as well

filter_topic_children = FILTER topic_parents BY 
	broaderTopicUri == 'Category:People'
  OR broaderTopicUri  == 'Category:Living_people'
  OR broaderTopicUri  == 'Category:Dead_people'
  OR broaderTopicUri  == 'Category:Missing_people'
  OR broaderTopicUri  == 'Category:Chronology'
  OR broaderTopicUri  == 'Category:Events'
  OR broaderTopicUri  == 'Category:Years'
  OR broaderTopicUri  == 'Category:Decads'
  OR broaderTopicUri  == 'Category:Days'
  OR broaderTopicUri  == 'Category:Dates'
  OR broaderTopicUri  == 'Category:Time'
  OR broaderTopicUri  == 'Category:Calendars'
  OR broaderTopicUri  == 'Category:Months'
  OR broaderTopicUri  == 'Year_of_birth_missing_%28living_people%29'
  OR broaderTopicUri  == 'Year_of_death_missing'
  OR broaderTopicUri  == 'Place_of_birth_missing_%28living_people%29'
  OR broaderTopicUri  == 'Category:Year_of_birth_unknown'
  OR broaderTopicUri  == 'Category:Year_of_birth_missing_%28living_people%29'
  OR broaderTopicUri  == 'Category:Articles_missing_birth_or_death_information'
  OR broaderTopicUri  == 'Category:Place_of_birth_missing_%28living_people%29'
  OR broaderTopicUri  == 'Category:Surnames'
  OR broaderTopicUri  == 'Category:Categories_by_language'
  OR broaderTopicUri  == 'Category:People_by_period'
  OR broaderTopicUri  == 'Category:Wikipedia_1.0_assessments';
  
topic_counts_children_join = JOIN topic_counts_filtered BY topicUri
	LEFT OUTER, filter_topic_children BY narrowerTopicUri;

topic_counts_children_filter = FILTER topic_counts_children_join BY broaderTopicUri IS NULL;

topic_counts_all_filter = FOREACH topic_counts_children_filter GENERATE
	topicUri, articleCount, narrowerTopicCount, broaderTopicCount;

-- filter those that have _by_ and Wikipedia on the category
topic_counts_all_filtered = FILTER topic_counts_all_filter BY
	not topicUri matches '.*Wikipedia_.*';
-- AGRM end

-- Project early: we don't need to load the abstract content: use NULL as
-- false marker to be able to combine them with missing abstracts later
articles = FOREACH article_abstracts GENERATE
   articleUri AS articleUri,
   (checkAbstract(articleAbstract) ? 1 : NULL) AS hasGoodAbstract;

STORE articles INTO 'workspace/articles_abstract_check.tsv';

-- Build are candidate matching article URI by removing the 'Category:'
-- part of the topic URI
candidate_grounded_topics = FOREACH topic_counts_all_filtered GENERATE
  topicUri, REPLACE(topicUri, 'Category:', '') AS candidatePrimaryArticleUri,
  articleCount, narrowerTopicCount, broaderTopicCount;

-- follow the redirect links if any
redirect_joined = JOIN candidate_grounded_topics BY candidatePrimaryArticleUri
  LEFT OUTER, redirects BY source;

redirected_candidate_grounded_topics = FOREACH redirect_joined GENERATE
  topicUri AS topicUri,
  (target IS NOT NULL ?
     target : candidatePrimaryArticleUri) AS candidatePrimaryArticleUri,
  articleCount AS articleCount;

-- Join on article abstracts to identify grounded topics
-- (topics that have a matching article with an abstract)
joined_candidate_grounded_topics = JOIN
  redirected_candidate_grounded_topics BY candidatePrimaryArticleUri LEFT OUTER,
  articles BY articleUri;

projected_candidate_grounded_topics = FOREACH joined_candidate_grounded_topics
  GENERATE
    redirected_candidate_grounded_topics::topicUri AS topicUri,
    (articles::hasGoodAbstract IS NOT NULL ?
      articles::articleUri : NULL) AS primaryArticleUri,
    redirected_candidate_grounded_topics::articleCount AS articleCount;

distinct_candidate_grounded_topics =
  DISTINCT projected_candidate_grounded_topics;

ordered_candidate_grounded_topics = ORDER distinct_candidate_grounded_topics
  BY articleCount DESC, topicUri;

SPLIT ordered_candidate_grounded_topics INTO
   grounded_topics IF primaryArticleUri IS NOT NULL,
   nongrounded_topics IF primaryArticleUri IS NULL;

projected_nongrounded_topics = FOREACH nongrounded_topics
  GENERATE topicUri, articleCount;

-- all topics, grounded and non grounded (primaryArticleUri can be NULL)
STORE distinct_candidate_grounded_topics INTO 'workspace/linked_topics.tsv';

-- only grounded topics (primaryArticleUri is not NULL)
STORE grounded_topics INTO 'workspace/grounded_topics.tsv';

-- only non-grounded topics (hence no primaryArticleUri either)
STORE projected_nongrounded_topics INTO 'workspace/nongrounded_topics.tsv';
