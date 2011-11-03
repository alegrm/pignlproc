/**
 * Create tsv files of articles and categories labels with 
 * their URI to create autofill field of topics
 */

SET default_parallel 20

-- Register the project jar to use the custom loaders and UDFs
REGISTER target/pignlproc-0.1.0-SNAPSHOT.jar
DEFINE SafeTsvText pignlproc.evaluation.SafeTsvText();
DEFINE CheckAbstract pignlproc.evaluation.CheckAbstract();

-- Defined available sources 
-- this has to be done for each language 
-- skos categories labels are only in english... 
-- TODO: some could be translated automatically if have a similar 
-- article page in the different languages
/*categories_labels = LOAD 'workspace/categories_labels.nt.bz2'
  USING pignlproc.storage.UriUriNTriplesLoader(
	'http://www.w3.org/2000/01/rdf-schema#label',
    'http://purl.org/dc/terms/subject')
  AS (uri: chararray, label: chararray);*/

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
  
STORE disambiguate_articles_join INTO 'workspace/disambiguate_articles_join.tsv';


SPLIT disambiguate_articles_join INTO
   disambiguate_articles IF disambuguation_uri IS NOT NULL,
   pure_articles IF disambuguation_uri IS NULL;

STORE disambiguate_articles INTO 'workspace/disambiguate_articles.tsv';

articles_wikipedia = FOREACH pure_articles
  GENERATE
    uri, label, SafeTsvText(abstract);
		
-- store tsv file to feed solr
STORE articles_wikipedia INTO 'workspace/articles_wikipedia.tsv';



