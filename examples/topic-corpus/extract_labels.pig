/**
 * Create tsv files of articles and categories labels with 
 * their URI to create autofill field of topics
 */

SET default_parallel 20

-- Register the project jar to use the custom loaders and UDFs
REGISTER target/pignlproc-0.1.0-SNAPSHOT.jar
DEFINE SafeTsvText pignlproc.evaluation.SafeTsvText();
DEFINE CheckAbstract pignlproc.evaluation.CheckAbstract();

-- This article extracrion has to be done for each language 
-- skos categories labels are only in english... 
-- TIP: some categories could be translated automatically if have a similar 
-- article page in the different languages
skos_categories = LOAD 'workspace/skos_categories_en.nt.bz2'
  USING pignlproc.storage.UriUriNTriplesLoader(
	'http://www.w3.org/1999/02/22-rdf-syntax-ns#type',
    'http://dbpedia.org/resource/',
	'http://www.w3.org/2004/02/skos/core#')
  AS (skos_uri: chararray, skos_concept: chararray);

article_labels = LOAD 'workspace/labels_en.nt.bz2'
  USING pignlproc.storage.UriStringLiteralNTriplesLoader(
    'http://www.w3.org/2000/01/rdf-schema#label',
    'http://dbpedia.org/resource/')
  AS (uri: chararray, label: chararray);

abstracts = LOAD 'workspace/long_abstracts_en.nt.bz2'
  USING pignlproc.storage.UriStringLiteralNTriplesLoader(
    'http://dbpedia.org/ontology/abstract',
    'http://dbpedia.org/resource/')
  AS (articleUri: chararray, abstract: chararray);

disambiguations = LOAD 'workspace/disambiguations_en.nt.bz2'
  USING pignlproc.storage.UriUriNTriplesLoader(
    'http://dbpedia.org/ontology/wikiPageDisambiguates',
    'http://dbpedia.org/resource/',
    'http://dbpedia.org/resource/')
  AS (disambuguation_uri: chararray, disambiguates: chararray);

disambiguation_uris = FOREACH disambiguations
  GENERATE disambuguation_uri;

-- any of these has to be on articles_wikipedia output
STORE disambiguation_uris INTO 'workspace/disambiguation_uris.tsv';

disambiguation_uris_distinct = DISTINCT disambiguation_uris;

filtered_article_abstracts = FILTER abstracts
  BY CheckAbstract(abstract);

articles = JOIN
  article_labels BY uri,
  filtered_article_abstracts BY articleUri;

-- elminate articles that are disambiguation pages
disambiguate_articles_join = JOIN 
  articles BY uri LEFT OUTER,
  disambiguation_uris_distinct BY disambuguation_uri;
  
SPLIT disambiguate_articles_join INTO
   disambiguate_articles IF disambuguation_uri IS NOT NULL,
   pure_articles IF disambuguation_uri IS NULL;

articles_wikipedia = FOREACH pure_articles
  GENERATE
    uri, label, SafeTsvText(abstract);
		
-- contains all uri, label and long abstract of articles of wikipedia
-- I've got 2375904 articles
STORE articles_wikipedia INTO 'workspace/articles_wikipedia1.tsv';

-- from those articles add information weather the article is also a category
-- or if a category contians an article 
-- this will provide me with grownded categories file.

categories_uris = FOREACH skos_categories
  GENERATE skos_uri;

categories_uris_distinct = DISTINCT categories_uris;

STORE categories_uris_distinct INTO 'workspace/categories_uris_distinct.tsv';

-- Build are candidate matching article URI by removing the 'Category:'
-- part of the topic URI
candidate_grounded_categories = FOREACH categories_uris_distinct GENERATE
  skos_uri, REPLACE(skos_uri, 'Category:', '') AS candidatePrimaryArticleUri;

-- Join on article abstracts to identify grounded topics
-- (topics that have a matching article)
join_categories_articles = JOIN
  articles_wikipedia BY uri LEFT OUTER,
  candidate_grounded_categories BY candidatePrimaryArticleUri 
  
articles_wikipedia2 = FOREACH join_categories_articles
  GENERATE
    uri, skos_uri, label, SafeTsvText(abstract);

STORE articles_wikipedia2 INTO 'workspace/articles_wikipedia2.tsv';

