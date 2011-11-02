/**
 * Create tsv files of articles and categories labels with 
 * their URI to create autofill field of topics
 */

SET default_parallel 20

-- Register the project jar to use the custom loaders and UDFs
REGISTER target/pignlproc-0.1.0-SNAPSHOT.jar

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


article_abstracts = LOAD 'workspace/long_abstracts_en.nt.bz2'
  USING pignlproc.storage.UriStringLiteralNTriplesLoader(
    'http://dbpedia.org/ontology/abstract',
    'http://dbpedia.org/resource/')
  AS (articleUri: chararray, abstract: chararray);

articles = JOIN
  article_labels BY uri,
  article_abstracts BY articleUri;

-- store tsv file to feed solr
STORE articles INTO 'workspace/articles_wikipedia.tsv';



